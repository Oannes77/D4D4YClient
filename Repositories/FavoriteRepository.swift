import Foundation

// MARK: - FavoriteError

/// 收藏操作错误。
enum FavoriteError: LocalizedError, Equatable {
    case notLoggedIn
    case pageUnavailable
    case network(String)
    case parseFailure(String)
    /// 请求已发出但回读未确认 —— 如实说明，不谎报成功。
    case unconfirmed(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "收藏需要登录：请先登录 4D4Y 账号。"
        case .pageUnavailable:
            return "页面不可用：站点返回拦截页（如 Cloudflare），请稍后在 App 内重试。"
        case .network(let s):
            return "网络失败：\(s)"
        case .parseFailure(let s):
            return "收藏列表解析失败：\(s)"
        case .unconfirmed(let s):
            return s
        }
    }
}

/// 一条服务器收藏。
struct FavoriteItem: Identifiable, Hashable {
    let tid: Int
    let title: String
    /// 次级说明（版块 / 作者 / 时间等）。
    let detail: String
    var id: Int { tid }
}

// MARK: - FavoriteRepository

/// 收藏数据层（Discuz `my.php?item=favorites&type=thread`）。
///
/// ⚠️ **本站按 User-Agent 分发两套模板**（详见 `docs/SiteFacts.md`），这一点是理解
/// 收藏问题的钥匙：
/// - 客户端（移动 UA）拿到的是精简的 `templates/wap/` 模板，它的帖子页把收藏 / 分享按钮
///   **整块写进了 HTML 注释** —— Sprint 12 看到的就是这一套，判断本身没错；
/// - 桌面 UA 的完整模板里这些入口是**活的**，`favoritewin` 弹层给出了权威地址：
///   `<a onclick="ajaxget('my.php?item=favorites&tid=<tid>', 'favorite_msg')">[收藏此主题]</a>`。
///
/// 所以「加入收藏」的首选地址就是上面这条（站点原样，不带 formhash），其余候选留作兜底。
/// **取消收藏的链接带独立收藏 id**（`favid`，由站点生成，靠 tid 推不出来），
/// 只能在运行时从收藏列表页解析出来 —— 红线：不硬编码表单参数。
///
/// 所有变更一律以**回读收藏列表**为唯一判据；确认不了就返回 `.unconfirmed`，绝不谎报成功。
final class FavoriteRepository {

    private let client: HTTPClient
    init(client: HTTPClient = HTTPClient()) { self.client = client }

    /// 收藏列表页（`type=thread` = 帖子收藏）。
    static let listPath = "my.php?item=favorites&type=thread"

    // MARK: 读取

    /// 收藏列表。
    func favorites() async -> Result<[FavoriteItem], FavoriteError> {
        switch await loadList() {
        case .success(let page): return .success(page.items)
        case .failure(let error): return .failure(error)
        }
    }

    // MARK: 变更

    /// 加入收藏。
    func add(tid: Int) async -> Result<Bool, FavoriteError> {
        await mutate(tid: tid, insert: true)
    }

    /// 取消收藏。
    func remove(tid: Int) async -> Result<Bool, FavoriteError> {
        await mutate(tid: tid, insert: false)
    }

    // MARK: 内部

    private struct Page {
        let items: [FavoriteItem]
        let tids: Set<Int>
        let formhash: String?
        /// 列表页里「删除该收藏」的原样链接（按 tid 归类）。
        /// 删除链接带独立 `favid`，构造不出来，只能运行时解析。
        let deleteHrefs: [Int: String]
    }

    private func loadList() async -> Result<Page, FavoriteError> {
        do {
            let req = try client.request(path: Self.listPath)
            let html = try await client.sendText(req)
            if PMListParser.isLoginGate(html) { return .failure(.notLoggedIn) }

            var items: [FavoriteItem] = []
            switch MySpaceParser.parse(html: html, kind: .threads) {
            case .entries(let list):
                items = list.compactMap { entry in
                    guard let tid = entry.threadID else { return nil }
                    return FavoriteItem(tid: tid, title: entry.title, detail: entry.detail)
                }
            case .empty:
                items = []
            case .requiresLogin:
                return .failure(.notLoggedIn)
            case .unsupported:
                // 有链接但一条都认不出：如实报错，**不要返回空列表假装「没有收藏」**。
                return .failure(.parseFailure("收藏列表结构未识别（站点模板可能已变化）"))
            }
            return .success(Page(items: items,
                                 tids: Set(items.map(\.tid)),
                                 formhash: Self.formhash(in: html),
                                 deleteHrefs: Self.deleteHrefs(in: html)))
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    private func mutate(tid: Int, insert: Bool) async -> Result<Bool, FavoriteError> {
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
                "my.php?item=favorites&tid=\(tid)",
                "my.php?item=favorites&tid=\(tid)\(hash)",
                "my.php?item=favorites&action=add&type=thread&tid=\(tid)\(hash)",
                "misc.php?action=favorite&tid=\(tid)&type=thread\(hash)"
            ]
        } else {
            var list: [String] = []
            // ① 列表页自己给出的删除链接（含站点生成的 favid）——最可靠，优先。
            if let href = page.deleteHrefs[tid] { list.append(href) }
            list.append(contentsOf: [
                "my.php?item=favorites&action=delete&type=thread&tid=\(tid)\(hash)",
                "my.php?item=favorites&action=delete&type=thread&favid=\(tid)\(hash)",
                "misc.php?action=favorite&action=delete&tid=\(tid)&type=thread\(hash)"
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
            // 回读确认：以收藏列表为唯一判据。
            switch await loadList() {
            case .success(let now):
                if now.tids.contains(tid) == insert { return .success(insert) }
            case .failure(let error):
                if error == .notLoggedIn { return .failure(error) }
            }
        }
        return .failure(.unconfirmed(insert
            ? "请求已发出，但收藏列表里没有出现这个帖子 —— 收藏接口可能与预期不同，未能确认成功。"
            : "请求已发出，但该帖仍在收藏列表里 —— 未能确认取消成功。"))
    }

    // MARK: 纯函数

    /// 页面里的 `formhash`（Discuz 8 位十六进制防 CSRF 令牌）。
    static func formhash(in html: String) -> String? {
        let patterns = [
            #"name=["']formhash["'][^>]*value=["']([0-9a-fA-F]{8})["']"#,
            #"formhash=([0-9a-fA-F]{8})"#
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let r = Range(m.range(at: 1), in: html) else { continue }
            return String(html[r])
        }
        return nil
    }

    /// 页面里所有 `viewthread.php?tid=` 的 tid（用于交叉确认）。
    static func tids(in html: String) -> Set<Int> {
        guard let re = try? NSRegularExpression(pattern: #"viewthread\.php\?tid=(\d+)"#) else { return [] }
        var set: Set<Int> = []
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            if let r = Range(m.range(at: 1), in: html), let tid = Int(html[r]) { set.insert(tid) }
        }
        return set
    }

    /// 收藏列表页里「删除该收藏」的原样链接（按 tid 归类）。
    ///
    /// 为什么必须解析而不能拼：Discuz 的删除链接带**独立的收藏 id**（`favid`），
    /// 由站点生成，用 tid 推不出来（红线：不硬编码表单参数）。
    ///
    /// 启发式：定位每个 `viewthread.php?tid=<tid>`（列表项的标题链接），
    /// 在其后 4000 字窗口内找第一个含 `action=delete` 的 href ——
    /// 列表行结构通常是「图标 · 标题链接 · 版块/时间 · 删除链接」。
    /// 找不到就跳过（调用方仍会退回构造候选，并且**无论如何都以回读列表为准**）。
    static func deleteHrefs(in html: String) -> [Int: String] {
        var result: [Int: String] = [:]
        guard let tidRe = try? NSRegularExpression(pattern: #"viewthread\.php\?tid=(\d+)"#) else { return result }
        let ns = html as NSString
        for m in tidRe.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(m.range(at: 1), in: html), let tid = Int(html[r]) else { continue }
            let window = ns.substring(from: m.range.location).prefix(4000)
            guard let href = firstDeleteHref(in: String(window)) else { continue }
            result[tid] = href.replacingOccurrences(of: "&amp;", with: "&")
        }
        return result
    }

    /// 文本里第一个形如 `href="...action=delete..."` 的链接。
    private static func firstDeleteHref(in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"href=["']([^"']*action=delete[^"']*)["']"#) else { return nil }
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
