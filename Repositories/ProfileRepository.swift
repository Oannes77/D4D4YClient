import Foundation

// MARK: - ProfileError
enum ProfileError: LocalizedError, Equatable {
    case requiresLogin
    case pageUnavailable
    case unsupportedStructure
    case network(String)

    var errorDescription: String? {
        switch self {
        case .requiresLogin:        return "会员资料需要登录：请先登录 4D4Y 账号。"
        case .pageUnavailable:      return "页面不可用：站点返回拦截页（如 Cloudflare），请稍后重试。"
        case .unsupportedStructure: return "暂时读不出会员资料：论坛页面结构可能已变化。"
        case .network(let s):       return "网络失败：\(s)"
        }
    }
}

// MARK: - ProfileRepositoryProtocol
protocol ProfileRepositoryProtocol {
    func profile(uid: Int, fallbackName: String) async -> Result<UserProfile, ProfileError>
}

// MARK: - ProfileRepository
/// 会员资料数据层：`space.php?uid=NNN`。
///
/// 该页**要求登录态**（游客实测返回「…无法进行此操作」+ 登录表单）。
/// 因此未登录时返回 `.requiresLogin`，用户卡改为显示「登录后可见资料」+ 登录入口，
/// 不再像旧版那样用内置示例数字（328 帖 / 9520 积分）冒充真实资料。
final class ProfileRepository: ProfileRepositoryProtocol {

    private let client: HTTPClient
    init(client: HTTPClient = HTTPClient()) { self.client = client }

    func profile(uid: Int, fallbackName: String) async -> Result<UserProfile, ProfileError> {
        guard uid > 0 else { return .failure(.unsupportedStructure) }
        do {
            let request = try client.request(path: "space.php?uid=\(uid)")
            let html = try await client.sendText(request)
            switch ProfileParser.parse(html: html, uid: uid, fallbackName: fallbackName) {
            case .profile(let profile): return .success(profile)
            case .requiresLogin:        return .failure(.requiresLogin)
            case .unsupported:          return .failure(.unsupportedStructure)
            }
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
