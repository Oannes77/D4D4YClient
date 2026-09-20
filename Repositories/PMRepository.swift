import Foundation

// MARK: - PMError
enum PMError: LocalizedError, Equatable {
    /// 游客 / 会话失效：pm.php 必须有登录态
    case requiresLogin
    /// Cloudflare 等拦截页
    case pageUnavailable
    /// 页面拿到了但结构未识别（模板改版），明确告知而不是显示空列表
    case unsupportedStructure
    /// 提交了但服务端未确认（回会话页读不到刚发的内容）
    case sendFailed(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .requiresLogin:        return "站内短信需要登录：请先登录 4D4Y 账号。"
        case .pageUnavailable:      return "页面不可用：站点返回拦截页（如 Cloudflare），请稍后重试。"
        case .unsupportedStructure: return "暂时读不出短信内容：论坛页面结构可能已变化。"
        case .sendFailed(let s):    return "短信未确认送达：\(s)"
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
    /// 发送一条私信
    func send(uid: Int, message: String) async -> Result<Void, PMError>
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

    /// 发送一条私信。
    ///
    /// 原则与回复 / 发帖一致：**不硬编码任何 POST 参数** —— 发送表单在运行时从
    /// 会话页 `pm.php?action=view&uid=N` 动态解析（action / hidden 字段 / formhash / textarea 名），
    /// 按论坛 charset=gbk 用 GB18030 百分比编码提交，最后**回会话页确认正文真的出现**才算成功。
    /// 未登录 → `.requiresLogin`；解析不到表单 → `.unsupportedStructure`；提交后读不到 → `.sendFailed`。
    func send(uid: Int, message: String) async -> Result<Void, PMError> {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard uid > 0 else { return .failure(.sendFailed("这条短信没有对应的用户 UID")) }
        guard !text.isEmpty else { return .failure(.sendFailed("内容为空")) }

        // 1) 打开会话页，动态解析发送表单
        let formResult: Result<DiscuzFormParser.Form, PMError> =
            await request(path: "pm.php?action=view&uid=\(uid)") { html in
                if PMListParser.isLoginGate(html) { return .failure(.requiresLogin) }
                guard let region = DiscuzFormParser.formRegion(in: html, requiring: "<textarea") else {
                    return .failure(.unsupportedStructure)
                }
                let form = DiscuzFormParser.parse(region)
                guard form.formhash != nil else { return .failure(.unsupportedStructure) }
                return .success(form)
            }

        let form: DiscuzFormParser.Form
        switch formResult {
        case .success(let parsed): form = parsed
        case .failure(let error):  return .failure(error)
        }

        // 2) 组装并提交（hidden 字段 + 正文 + 提交按钮，全部来自运行时解析）
        var fields = form.hiddenFields
        fields[form.messageFieldName] = text
        if let submit = form.submitField { fields[submit.name] = submit.value }

        let action = form.action.replacingOccurrences(of: "&amp;", with: "&")
        guard let url = URL(string: action, relativeTo: HTTPClient.baseURL)?.absoluteURL else {
            return .failure(.sendFailed("提交地址无效：\(action)"))
        }
        var req = HTTPRequest(method: .post, url: url,
                              headers: ["Content-Type": "application/x-www-form-urlencoded"])
        req.body = DiscuzFormParser.gbkFormURLEncoded(fields)

        do {
            let echoed = try await client.sendText(req)
            if PMListParser.isLoginGate(echoed) { return .failure(.requiresLogin) }
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }

        // 3) 成功判定：回会话页确认正文出现（不依赖返回文案，不本地伪造）
        return await request(path: "pm.php?action=view&uid=\(uid)") { html in
            if PMListParser.isLoginGate(html) { return .failure(.requiresLogin) }
            let probe = String(text.prefix(12))
            return html.contains(probe)
                ? .success(())
                : .failure(.sendFailed("服务端未确认：会话里暂时读不到刚发送的内容"))
        }
    }

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
