import Foundation
import Combine

/// 会话过期通知：任意响应命中「您还未登录」时由 `HTTPClient` 统一发出。
extension Notification.Name {
    static let d4d4ySessionExpired = Notification.Name("D4D4Y.SessionExpired")
}

/// 会话管理器：编排登录 / 登出 / 启动恢复，对外发布 `state` 供 UI 订阅。
///
/// 安全约束（与 Sprint 6 要求一致）：
/// - 明文密码**绝不**离开 `LoginRepository`；本类与 Keychain 均不持有密码。
/// - 鉴权凭据（`cdb_auth`）持久化于 **Keychain**，不入 SwiftData。
/// - 不绕过任何权限 / 验证码 / Cloudflare；验证码场景返回明确错误。
@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var state: AuthenticationState = .guest
    /// 登录页表单快照（含安全提问选项）。未取到时为 nil，UI 走标准兜底列表。
    @Published private(set) var loginForm: LoginForm?
    /// 正在拉取登录表单（UI 展示 loading）。
    @Published private(set) var isLoadingLoginForm = false

    static let shared = SessionManager()

    private let repository = LoginRepository()

    private init() {
        // 统一掉线检测：HTTPClient 识别到「您还未登录」时通知此处理。
        NotificationCenter.default.addObserver(
            forName: .d4d4ySessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.markExpired() }
        }
    }

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

    // MARK: - 登录表单（安全提问选项）

    /// 预取登录页表单，供 UI 展示真实安全提问列表。
    /// 已取到则直接复用（避免重复 GET 导致 formhash 变化）。
    func loadLoginForm() async {
        guard loginForm == nil else { return }
        isLoadingLoginForm = true
        defer { isLoadingLoginForm = false }
        switch await repository.loadLoginForm() {
        case .success(let form):
            loginForm = form
        case .failure(let error):
            let desc = error.errorDescription ?? "未知错误"
            Log.network.error("登录表单获取失败: \(desc, privacy: .public)")
            // 失败不阻塞：UI 回退到标准安全提问列表。
        }
    }

    // MARK: - 登录

    /// 执行登录。整个过程中 `password` 仅作为参数传至 `LoginRepository` 用于计算 MD5，
    /// 本方法**不保存、不打印**密码。
    func login(username: String,
               password: String,
               questionID: Int = 0,
               answer: String = "",
               rememberMe: Bool = true) async {
        guard !username.isEmpty, !password.isEmpty else {
            self.state = .failed(.loginFailed("请输入用户名和密码"))
            return
        }
        self.state = .authenticating

        // 表单缺失时先取一次，保证 formhash 与 sid 同源。
        let form: LoginForm
        if let cached = loginForm {
            form = cached
        } else {
            switch await repository.loadLoginForm() {
            case .success(let f):
                form = f
                loginForm = f
            case .failure(let error):
                clearAuthCookies()
                self.state = .failed(error)
                return
            }
        }

        let result = await repository.submit(form: form,
                                             username: username,
                                             password: password,
                                             questionID: questionID,
                                             answer: answer,
                                             rememberMe: rememberMe)
        switch result {
        case .success(let session):
            self.state = .authenticated(session)
        case .failure(let error):
            // 失败时清掉可能部分写入的 Cookie，避免脏状态；
            // 同时丢弃表单缓存，下次登录重新取 formhash（连续失败会触发验证码）。
            clearAuthCookies()
            loginForm = nil
            self.state = .failed(error)
        }
    }

    // MARK: - 掉线 / 登出

    /// 运行期掉线：仅在"原本已登录"时生效，避免登录流程中的游客响应误判。
    func markExpired() {
        guard state.isAuthenticated else { return }
        KeychainStore.shared.clear()
        clearAuthCookies()
        loginForm = nil
        self.state = .guest
        Self.clearServerBackedCaches()
    }

    /// 退出登录：本地清凭据为权威行为；同时尽力通知服务端作废会话（best-effort，不阻塞）。
    func logout() {
        KeychainStore.shared.clear()
        clearAuthCookies()
        loginForm = nil
        Task { await bestEffortServerLogout() }
        self.state = .guest
        Self.clearServerBackedCaches()
    }

    /// 清掉「服务器真源」类的内存缓存。
    ///
    /// 收藏 / 关注都是**服务器上的数据**（`my.php?item=…`）。退出登录后若还留着上一账号的
    /// tid 集合，详情页会显示成已收藏 / 已关注的星标与铃铛 —— 那是在替游客「假装」服务器状态，
    /// 属于必须避免的假象。所以登出与掉线都清一次。
    private static func clearServerBackedCaches() {
        Task { @MainActor in
            FavoritesStore.shared.clear()
            AttentionStore.shared.clear()
        }
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
            guard let formhash = LoginFormParser.hiddenValue(html: page, name: "formhash") else { return }
            let logoutURL = LoginFlowReference.logoutPath + "&formhash=" + formhash
            _ = try? await client.sendText(try client.request(path: logoutURL))
        } catch {
            // 静默：登出以本地清凭据为准
        }
    }
}
