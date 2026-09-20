import Foundation

// MARK: - BuddyError

/// 好友操作错误。与其它数据层一致：**绝不静默失败，也不假装成功**。
enum BuddyError: LocalizedError, Equatable {
    case notLoggedIn
    case pageUnavailable
    case network(String)
    case parseFailure(String)
    /// 请求已发出，但回读结果与预期不符 —— 如实说明「没能确认」，不谎报成功。
    case unconfirmed(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "会话无效：当前为游客态，请先登录后再操作好友。"
        case .pageUnavailable:
            return "页面不可用：站点返回拦截页（如 Cloudflare），请稍后在 App 内重试。"
        case .network(let s):
            return "网络失败：\(s)"
        case .parseFailure(let s):
            return "页面解析失败：\(s)"
        case .unconfirmed(let s):
            return s
        }
    }
}

/// 一位好友。
struct BuddyEntry: Identifiable, Hashable {
    let uid: Int
    let name: String
    var id: Int { uid }
}

// MARK: - BuddyRepository

/// 好友数据层（Discuz `my.php?item=buddylist`）。
///
/// 真实接口（由用户在真机上确认过的链接形式）：
/// - 好友列表：`my.php?item=buddylist&`
/// - 添加好友：`my.php?item=buddylist&newbuddyid=<uid>&buddysubmit=yes`
/// - 删除好友：`my.php?item=buddylist&action=delete&friendid=<uid>&buddysubmit=yes`
///
/// 设计原则：
/// 1. **不做乐观更新** —— 每个变更请求发出后，都回读一次好友列表，
///    以「列表里到底有没有这个人」作为唯一判据；结果不符就返回 `.unconfirmed` 并如实说明。
/// 2. 登录门（`您还未登录`）→ `.notLoggedIn`，界面给登录入口，不绕过。
final class BuddyRepository {

    private let client: HTTPClient
    init(client: HTTPClient = HTTPClient()) { self.client = client }

    /// 好友列表页（末尾的 `&` 是站点真实形式，保留）。
    static let listPath = "my.php?item=buddylist&"

    // MARK: 读取

    /// 拉取好友列表。解析复用 `MySpaceParser` 的用户型抽取（`space.php?uid=` 去重）。
    func buddies() async -> Result<[BuddyEntry], BuddyError> {
        do {
            let req = try client.request(path: Self.listPath)
            let html = try await client.sendText(req)
            if PMListParser.isLoginGate(html) { return .failure(.notLoggedIn) }

            switch MySpaceParser.parse(html: html, kind: .friends) {
            case .entries(let list):
                let buddies = list.compactMap { entry -> BuddyEntry? in
                    guard let uid = entry.userID else { return nil }
                    return BuddyEntry(uid: uid, name: entry.title)
                }
                Log.network.info("BuddyRepository: 好友 \(buddies.count, privacy: .public) 位")
                return .success(buddies)
            case .empty:
                return .success([])
            case .requiresLogin:
                return .failure(.notLoggedIn)
            case .unsupported:
                return .failure(.parseFailure("好友列表结构未识别（站点模板可能已变化）"))
            }
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    /// 该 uid 是否已在好友列表里（用于用户卡显示「加好友 / 已是好友」）。
    func isBuddy(uid: Int) async -> Result<Bool, BuddyError> {
        switch await buddies() {
        case .success(let list):  return .success(list.contains { $0.uid == uid })
        case .failure(let error): return .failure(error)
        }
    }

    // MARK: 变更

    /// 加好友，成功后回读列表确认。
    func add(uid: Int) async -> Result<Bool, BuddyError> {
        await mutate(path: "my.php?item=buddylist&newbuddyid=\(uid)&buddysubmit=yes",
                     uid: uid, expecting: true)
    }

    /// 删好友，成功后回读列表确认。
    func remove(uid: Int) async -> Result<Bool, BuddyError> {
        await mutate(path: "my.php?item=buddylist&action=delete&friendid=\(uid)&buddysubmit=yes",
                     uid: uid, expecting: false)
    }

    /// 执行一次变更请求，随后用好友列表这一**唯一事实来源**确认结果。
    private func mutate(path: String, uid: Int, expecting shouldExist: Bool) async -> Result<Bool, BuddyError> {
        do {
            let req = try client.request(path: path)
            let html = try await client.sendText(req)
            if PMListParser.isLoginGate(html) { return .failure(.notLoggedIn) }

            switch await buddies() {
            case .success(let list):
                let exists = list.contains { $0.uid == uid }
                guard exists == shouldExist else {
                    return .failure(.unconfirmed(shouldExist
                        ? "请求已发送，但好友列表里还没有出现该用户（可能需要在站内确认，或站点未生效）。"
                        : "请求已发送，但该用户仍在好友列表里（可能没有删成功）。"))
                }
                return .success(exists)
            case .failure(let error):
                return .failure(error)
            }
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
