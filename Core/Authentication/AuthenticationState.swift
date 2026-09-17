import Foundation

/// 登录阶段可能产生的、可展示给用户的错误。
///
/// 设计原则（与 Sprint 6 安全要求一致）：
/// - 明文密码**绝不**进入任何错误文案。
/// - 若服务端要求图形验证码（seccode），返回 `.captchaRequired` 明确报错，**绝不绕过**。
enum AuthenticationError: LocalizedError, Equatable {
    /// 网络 / 传输层失败（Cloudflare 质询、超时、断网等）。
    case network(String)
    /// 登录页表单解析失败（取不到 formhash / sid），或登录后取不到鉴权 Cookie。
    case invalidResponse
    /// 服务端要求图形验证码（seccode）。当前版本不支持输入 → 明确报错，不绕过。
    case captchaRequired
    /// 凭据被服务端拒绝（用户名/密码错误、安全提问不匹配等）。
    case loginFailed(String)
    /// 其他未归类错误。
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .network(let m):      return "网络错误：\(m)"
        case .invalidResponse:     return "登录页解析失败，请稍后重试"
        case .captchaRequired:     return "服务器要求输入验证码，当前版本暂不支持，请使用浏览器登录"
        case .loginFailed(let m):   return m
        case .unknown(let m):       return m
        }
    }
}

/// 认证状态枚举。
///
/// - `.guest`：游客态（默认），仅可浏览公开内容。
/// - `.authenticating`：登录请求进行中（UI 展示 loading）。
/// - `.authenticated`：已登录，持有本地会话快照（不含明文密码 / 原始 Cookie 以外凭据）。
/// - `.failed`：最近一次登录尝试失败，携带可展示错误；可重试。
enum AuthenticationState: Equatable {
    /// 游客态（默认）：无有效会话，仅可浏览公开内容。
    case guest
    /// 登录请求进行中。
    case authenticating
    /// 已登录态：持有本地会话表示。
    case authenticated(UserSession)
    /// 登录失败（瞬时错误，UI 提示；可重试）。
    case failed(AuthenticationError)

    /// 是否已登录（供其它视图条件渲染）。
    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    /// 当前会话（仅登录态非 nil）。
    var session: UserSession? {
        if case .authenticated(let s) = self { return s }
        return nil
    }
}
