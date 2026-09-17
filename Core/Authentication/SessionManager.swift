import Foundation
import Combine

/// 会话管理器：编排登录 / 登出 / 启动恢复，对外发布 `state` 供 UI 订阅。
///
/// 安全约束（与 Sprint 6 要求一致）：
/// - 明文密码**绝不**离开 `LoginRepository`；本类与 Keychain 均不持有密码。
/// - 鉴权凭据（`cdb_auth`）持久化于 **Keychain**，不入 SwiftData。
/// - 不绕过任何权限 / 验证码 / Cloudflare；验证码场景返回明确错误。
@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var state: AuthenticationState = .guest

    static let shared = SessionManager()

    private let repository = LoginRepository()

    private init() {}

    // MARK: - 演示模式（仅截图用，不触及真实鉴权流程）

    /// 仅演示/截图模式：把会话置为已登录，使回复编辑器呈现「输入框 + 紫色发送」。
    /// 无网络、无 Keychain；正常构建中不会被调用。
    func enterDemoSession() {
        self.state = .authenticated(UserSession(uid: 1, username: "演示用户", loginTime: .now))
    }

    // MARK: - 启动恢复

    /// App 启动（或 Scene 出现）时调用：若 Keychain 存有有效凭据，
    /// 注入 `HTTPCookieStorage.shared` 并恢复到 `.authenticated`（乐观恢复，免网络往返）。
    func restore() {
        guard let token = KeychainStore.shared.loadAuthToken() else {
            self.state = .guest
            return
        }
        injectCookie(name: LoginFlowReference.AuthCookie.auth, value: token)
        if let (username, uid) = KeychainStore.shared.loadSession() {
            self.state = .authenticated(UserSession(uid: uid, username: username, loginTime: .now))
        } else {
            self.state = .authenticated(UserSession(uid: 0, username: "已登录用户", loginTime: .now))
        }
    }

    // MARK: - 登录

    /// 执行登录。整个过程中 `password` 仅作为参数传至 `LoginRepository` 用于计算 MD5，
    /// 本方法**不保存、不打印**密码。
    func login(username: String, password: String) async {
        guard !username.isEmpty, !password.isEmpty else {
            self.state = .failed(.loginFailed("请输入用户名和密码"))
            return
        }
        self.state = .authenticating
        let result = await repository.login(username: username, password: password)
        switch result {
        case .success(let session):
            self.state = .authenticated(session)
        case .failure(let error):
            // 失败时清掉可能部分写入的 Cookie，避免脏状态。
            clearAuthCookies()
            self.state = .failed(error)
        }
    }

    // MARK: - 登出

    /// 退出登录：本地清凭据为权威行为；同时尽力通知服务端作废会话（best-effort，不阻塞）。
    func logout() {
        KeychainStore.shared.clear()
        clearAuthCookies()
        Task { await bestEffortServerLogout() }
        self.state = .guest
    }

    // MARK: - 私有

    /// 把鉴权 Cookie 注入共享存储，供 `HTTPClient`（默认配置即 `HTTPCookieStorage.shared`）
    /// 在后续请求自动携带，实现"登录态浏览"。
    private func injectCookie(name: String, value: String) {
        guard let url = URL(string: LoginFlowReference.forumBaseURL) else { return }
        let cookie = HTTPCookie(properties: [
            .domain: url.host ?? "www.4d4y.com",
            .path: url.path,                 // "/forum/"
            .name: name,
            .value: value,
            .secure: true,
            .expires: Date().addingTimeInterval(60 * 60 * 24 * 30)
        ])
        if let cookie {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private func clearAuthCookies() {
        HTTPCookieStorage.shared.cookies?.forEach { c in
            if c.name == LoginFlowReference.AuthCookie.auth ||
               c.name == LoginFlowReference.AuthCookie.sid {
                HTTPCookieStorage.shared.deleteCookie(c)
            }
        }
    }

    /// 服务端登出（best-effort）：GET 取 formhash → GET logout。失败静默，本地登出为准。
    private func bestEffortServerLogout() async {
        do {
            let client = HTTPClient()
            let page = try await client.sendText(try client.request(path: LoginFlowReference.logoutPath))
            guard let formhash = extractFormhash(from: page) else { return }
            let logoutURL = LoginFlowReference.logoutPath + "&formhash=" + formhash
            _ = try? await client.sendText(try client.request(path: logoutURL))
        } catch {
            // 静默：登出以本地清凭据为准
        }
    }

    private func extractFormhash(from html: String) -> String? {
        let tagPattern = "<input[^>]*name=[\"']formhash[\"'][^>]*>"
        guard let tagRegex = try? NSRegularExpression(pattern: tagPattern, options: .caseInsensitive),
              let tagMatch = tagRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let tagRange = Range(tagMatch.range, in: html) else { return nil }
        let tag = String(html[tagRange])
        let valPattern = "value=[\"']([^\"']*)[\"']"
        guard let valRegex = try? NSRegularExpression(pattern: valPattern, options: .caseInsensitive),
              let valMatch = valRegex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let valRange = Range(valMatch.range(at: 1), in: tag) else { return nil }
        return String(tag[valRange])
    }
}
