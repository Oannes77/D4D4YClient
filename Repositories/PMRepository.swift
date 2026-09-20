import Foundation

// MARK: - PMError
enum PMError: LocalizedError, Equatable {
    /// 游客 / 会话失效：pm.php 必须有登录态
    case requiresLogin
    /// Cloudflare 等拦截页
    case pageUnavailable
    /// 页面拿到了但结构未识别（模板改版），明确告知而不是显示空列表
    case unsupportedStructure
    case network(String)

    var errorDescription: String? {
        switch self {
        case .requiresLogin:        return "站内短信需要登录：请先登录 4D4Y 账号。"
        case .pageUnavailable:      return "页面不可用：站点返回拦截页（如 Cloudflare），请稍后重试。"
        case .unsupportedStructure: return "暂时读不出短信内容：论坛页面结构可能已变化。"
        case .network(let s):       return "网络失败：\(s)"
        }
    }
}

// MARK: - PMRepositoryProtocol
protocol PMRepositoryProtocol {
    /// 收件箱（站内短信）
    func inbox() async -> Result<[PrivateMessage], PMError>
    /// 系统消息
    func systemMessages() async -> Result<[PrivateMessage], PMError>
    /// 与某个用户的私信往来（用于会话气泡）
    func conversation(uid: Int, userName: String, myUserID: Int?) async -> Result<PMConversation, PMError>
}

// MARK: - PMRepository
/// 站内短信数据层：`pm.php`（收件箱 / 系统消息 / 与某人的往来）。
///
/// 全部接口都**要求登录态**：Cookie 由 `HTTPCookieStorage.shared` 自动携带
/// （`SessionManager` 登录成功后注入），本类不接触任何凭据。
/// 游客态返回 `.requiresLogin`，界面给登录入口，不伪造内容。
final class PMRepository: PMRepositoryProtocol {

    private let client: HTTPClient
    init(client: HTTPClient = HTTPClient()) { self.client = client }

    func inbox() async -> Result<[PrivateMessage], PMError> {
        await list(path: "pm.php?filter=privatepm", system: false)
    }

    func systemMessages() async -> Result<[PrivateMessage], PMError> {
        await list(path: "pm.php?filter=systempm", system: true)
    }

    func conversation(uid: Int, userName: String, myUserID: Int?) async -> Result<PMConversation, PMError> {
        guard uid > 0 else { return .failure(.unsupportedStructure) }
        return await request(path: "pm.php?action=view&uid=\(uid)") { html in
            switch PMConversationParser.parse(html: html, myUserID: myUserID) {
            case .bubbles(let bubbles):
                guard !bubbles.isEmpty else { return .failure(.unsupportedStructure) }
                return .success(PMConversation(userID: uid, userName: userName, bubbles: bubbles))
            case .requiresLogin:
                return .failure(.requiresLogin)
            case .unsupported:
                return .failure(.unsupportedStructure)
            }
        }
    }

    // MARK: - 私有

    private func list(path: String, system: Bool) async -> Result<[PrivateMessage], PMError> {
        await request(path: path) { html in
            switch PMListParser.parse(html: html, systemSegment: system) {
            case .messages(let items): return .success(items)
            case .empty:               return .success([])
            case .requiresLogin:       return .failure(.requiresLogin)
            case .unsupported:         return .failure(.unsupportedStructure)
            }
        }
    }

    /// 统一的「请求 + 解析」骨架：网络 / 拦截页错误在此归一。
    private func request<T>(path: String,
                            transform: (String) -> Result<T, PMError>) async -> Result<T, PMError> {
        do {
            let request = try client.request(path: path)
            let html = try await client.sendText(request)
            return transform(html)
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
