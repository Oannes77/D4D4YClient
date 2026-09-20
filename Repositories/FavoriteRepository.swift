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
/// ⚠️ 站点模板把帖子页的收藏入口（`favoritewin` 弹窗）**整块注释掉了**，
/// 所以「加入收藏」的提交地址无法从页面里解析出来。这里的做法是：
/// 1. 先读收藏列表页，取出 `formhash` 与现有收藏集合；
/// 2. 按 Discuz! 7.2 的几种标准形式**依次尝试**提交；
/// 3. 每次尝试后**回读收藏列表**，以「该 tid 是否出现在列表里」为唯一判据。
///
/// 全部候选都不成功 → 返回 `.unconfirmed` 并如实说明，**绝不谎报收藏成功**。
/// （真机登录后可据实际响应把候选收敛为确定的那一个。）
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
                                 formhash: Self.formhash(in: html)))
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
        let candidates: [String] = insert
            ? ["my.php?item=favorites&action=add&type=thread&tid=\(tid)\(hash)",
               "misc.php?action=favorite&tid=\(tid)&type=thread\(hash)",
               "my.php?item=favorites&action=add&type=thread&favid=\(tid)\(hash)"]
            : ["my.php?item=favorites&action=delete&type=thread&tid=\(tid)\(hash)",
               "my.php?item=favorites&action=delete&type=thread&favid=\(tid)\(hash)",
               "misc.php?action=favorite&action=delete&tid=\(tid)&type=thread\(hash)"]

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
}
