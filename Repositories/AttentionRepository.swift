import Foundation

// MARK: - AttentionError

/// 「关注主题」操作错误。
enum AttentionError: LocalizedError, Equatable {
    case notLoggedIn
    case pageUnavailable
    case network(String)
    case parseFailure(String)
    /// 请求已发出但回读未确认 —— 如实说明，不谎报成功。
    case unconfirmed(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "关注需要登录：请先登录 4D4Y 账号。"
        case .pageUnavailable:
            return "页面不可用：站点返回拦截页（如 Cloudflare），请稍后在 App 内重试。"
        case .network(let s):
            return "网络失败：\(s)"
        case .parseFailure(let s):
            return "关注列表解析失败：\(s)"
        case .unconfirmed(let s):
            return s
        }
    }
}

/// 一条「我关注的主题」。
struct AttentionItem: Identifiable, Hashable {
    let tid: Int
    let title: String
    /// 次级说明（版块 / 状态等）。
    let detail: String
    var id: Int { tid }
}

// MARK: - AttentionRepository

/// 「关注主题」数据层（Discuz `my.php?item=attention`）。
///
/// ⚠️ **先说清「关注」是什么** —— 这里踩过一个坑：
/// Discuz! 7.2 的 `attention` 关注的是**主题**，不是人。
/// 站点 PC 模板的 `favoritewin` 弹层把两个入口并排放着，原文是：
/// ```html
/// <a onclick="ajaxget('my.php?item=favorites&tid=193033', 'favorite_msg')">[收藏此主题]</a>
/// <a onclick="ajaxget('my.php?item=attention&action=add&tid=193033', 'favorite_msg')">[关注此主题的新回复]</a>
/// ```
/// 两个地址的参数都是 **tid**（不是 uid）—— 所以「关注」= 关注帖子，
/// 「我的 → 关注」这一栏列出的也是**主题**（帖子型列表）。
/// （用户之间的关注是 Discuz X 系列才有的功能，7.2 没有。）
///
/// ⚠️ 另外，WAP 模板的帖子页把收藏 / 分享整块注释掉了，**但关注接口并不受影响** ——
/// `my.php?item=attention` 依然真实存在（详见 `docs/SiteFacts.md`）。
///
/// 取消关注的链接站点没有在页面里给出（`favoritewin` 只有 add），
/// 所以删除走「列表页自带的删除链接优先 + 候选兜底 + **回读列表确认**」的路子：
/// 确认不了就返回 `.unconfirmed`，绝不谎报成功。
final class AttentionRepository {

    private let client: HTTPClient
    init(client: HTTPClient = HTTPClient()) { self.client = client }

    /// 关注列表页。
    static let listPath = "my.php?item=attention"

    // MARK: 读取

    /// 我关注的主题列表。
    func list() async -> Result<[AttentionItem], AttentionError> {
        switch await loadList() {
        case .success(let page): return .success(page.items)
        case .failure(let error): return .failure(error)
        }
    }

    // MARK: 变更

    /// 关注该主题的新回复。
    func add(tid: Int) async -> Result<Bool, AttentionError> {
        await mutate(tid: tid, insert: true)
    }

    /// 取消关注。
    func remove(tid: Int) async -> Result<Bool, AttentionError> {
        await mutate(tid: tid, insert: false)
    }

    // MARK: 内部

    private struct Page {
        let items: [AttentionItem]
        let tids: Set<Int>
        let formhash: String?
        /// 列表页里「取消关注」的原样链接（按 tid 归类）。
        let deleteHrefs: [Int: String]
    }

    private func loadList() async -> Result<Page, AttentionError> {
        do {
            let req = try client.request(path: Self.listPath)
            let html = try await client.sendText(req)
            if PMListParser.isLoginGate(html) { return .failure(.notLoggedIn) }

            var items: [AttentionItem] = []
            switch MySpaceParser.parse(html: html, kind: .follows) {
            case .entries(let list):
                items = list.compactMap { entry in
                    guard let tid = entry.threadID else { return nil }
                    return AttentionItem(tid: tid, title: entry.title, detail: entry.detail)
                }
            case .empty:
                items = []
            case .requiresLogin:
                return .failure(.notLoggedIn)
            case .unsupported:
                // 有链接但一条都认不出：如实报错，**不要返回空列表假装「没有关注」**。
                return .failure(.parseFailure("关注列表结构未识别（站点模板可能已变化）"))
            }
            return .success(Page(items: items,
                                 tids: Set(items.map(\.tid)),
                                 formhash: FavoriteRepository.formhash(in: html),
                                 deleteHrefs: FavoriteRepository.deleteHrefs(in: html)))
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    private func mutate(tid: Int, insert: Bool) async -> Result<Bool, AttentionError> {
        let page: Page
        switch await loadList() {
        case .success(let p): page = p
        case .failure(let error): return .failure(error)
        }

        // 已经处于目标状态：直接返回，不必发请求。
        if page.tids.contains(tid) == insert { return .success(insert) }

        let hash = page.formhash.map { "&formhash=\($0)" } ?? ""
        let candidates: [String]
        if insert {
            candidates = [
                // ① 权威地址：站点 PC 模板 `favoritewin` 弹层里的原样链接（不带 formhash）。
                "my.php?item=attention&action=add&tid=\(tid)",
                "my.php?item=attention&action=add&tid=\(tid)\(hash)",
                "my.php?item=attention&tid=\(tid)\(hash)",
                "misc.php?action=attention&action=add&tid=\(tid)\(hash)"
            ]
        } else {
            var list: [String] = []
            // ① 列表页自己给出的删除链接 —— 最可靠，优先。
            if let href = page.deleteHrefs[tid] { list.append(href) }
            list.append(contentsOf: [
                "my.php?item=attention&action=delete&tid=\(tid)\(hash)",
                "my.php?item=attention&action=delete&favid=\(tid)\(hash)",
                "misc.php?action=attention&action=delete&tid=\(tid)\(hash)"
            ])
            candidates = list
        }

        for path in candidates {
            do {
                let req = try client.request(path: path)
                _ = try await client.sendText(req)
            } catch let e as NetworkError {
                if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
                continue
            } catch {
                continue
            }
            // 回读确认：以关注列表为唯一判据。
            switch await loadList() {
            case .success(let now):
                if now.tids.contains(tid) == insert { return .success(insert) }
            case .failure(let error):
                if error == .notLoggedIn { return .failure(error) }
            }
        }
        return .failure(.unconfirmed(insert
            ? "请求已发出，但关注列表里没有出现这个主题 —— 关注接口可能与预期不同，未能确认成功。"
            : "请求已发出，但该主题仍在关注列表里 —— 未能确认取消成功。"))
    }
}
