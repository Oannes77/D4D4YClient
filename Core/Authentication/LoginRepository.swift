import Foundation
import CryptoKit

/// 登录数据层：复刻 Discuz! 7.2 真实登录链路（Sprint 5B 实证）。
///
/// 流程：
/// `GET logging.php?action=login` → 解析隐藏字段(sid / formhash / referer)与安全提问选项 →
/// `pwmd5(password)`(4D4Y: 单 MD5 `hex_md5(raw)`) → `POST logging.php?action=login&loginsubmit=yes` →
/// `my.php` 登录态校验（含二段"可解析用户状态"校验）→ 捕获 `cdb_auth` → 返回 `UserSession`。
///
/// **复用** `HTTPClient`（`send` 已原生支持 POST，并经 `HTTPCookieStorage.shared` 管理 Cookie），
/// **不修改** `HTTPClient` / 其它 Parser / `ForumRepository`。
///
/// 安全：
/// - 明文密码仅在内存中用于计算 MD5，**绝不存储、绝不打印、绝不落 Keychain**。
/// - 若服务端要求验证码（seccode），返回 `.captchaRequired` 明确错误，**绝不绕过**。
final class LoginRepository {

    private let client: HTTPClient

    init(client: HTTPClient = HTTPClient()) {
        self.client = client
    }

    // MARK: - ① 拉取登录表单

    /// GET 登录页，解析出提交所需的隐藏字段与安全提问选项。
    ///
    /// 必须**先取表单再提交**：`formhash` 与 `sid` 绑定，两次 GET 会得到不同 formhash。
    func loadLoginForm() async -> Result<LoginForm, AuthenticationError> {
        let html: String
        do {
            let req = try client.request(path: LoginFlowReference.realLoginPath)
            html = try await client.sendText(req)
        } catch {
            return .failure(.network(Self.message(from: error)))
        }

        guard let form = LoginFormParser.parse(html: html) else {
            return .failure(.invalidResponse)
        }
        return .success(form)
    }

    // MARK: - ② 提交登录

    /// 使用已取到的表单提交一次登录。
    ///
    /// - Parameters:
    ///   - form: `loadLoginForm()` 得到的表单快照（保证 formhash 与 sid 同源）。
    ///   - username: 用户名 / UID / Email（中文用户名按 GBK 编码提交）。
    ///   - password: 明文密码，仅在此作用域内计算 MD5，用完即弃。
    ///   - questionID: 安全提问 `questionid`（0 = 未设置）。
    ///   - answer: 安全提问答案（**必须 GBK 编码**，否则服务端解出乱码导致失败）。
    ///   - rememberMe: 是否勾选"记住登录状态"（30 天）。
    func submit(form: LoginForm,
                username: String,
                password: String,
                questionID: Int,
                answer: String,
                rememberMe: Bool) async -> Result<UserSession, AuthenticationError> {
        // 验证码：只识别、明确报错，绝不绕过。
        if form.requiresCaptcha { return .failure(.captchaRequired) }

        // 明文密码不离开此作用域。
        let hashed = Self.pwmd5(password)

        // 字段顺序贴近浏览器表单，便于服务端解析。
        // gbk=true 的字段按页面 charset=gbk 编码（中文用户名 / 安全提问答案）。
        let fields: [(key: String, value: String, gbk: Bool)] = [
            (LoginFlowReference.FormField.sid,         form.sid,                     false),
            (LoginFlowReference.FormField.formhash,    form.formhash,                false),
            (LoginFlowReference.FormField.referer,     form.referer,                 false),
            (LoginFlowReference.FormField.loginfield,  "username",                   false),
            (LoginFlowReference.FormField.username,    username,                     true),
            (LoginFlowReference.FormField.password,    hashed,                       false),
            (LoginFlowReference.FormField.questionid,  String(questionID),           false),
            (LoginFlowReference.FormField.answer,      answer,                       true),
            (LoginFlowReference.FormField.cookietime,  rememberMe ? "2592000" : "0", false),
            (LoginFlowReference.FormField.loginsubmit, "true",                       false)
        ]

        guard let postURL = URL(string: LoginFlowReference.realLoginSubmitURL) else {
            return .failure(.invalidResponse)
        }
        let postReq = HTTPRequest(
            method: .post,
            url: postURL,
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                "Referer": LoginFlowReference.realLoginURL,
                "Origin": "https://www.4d4y.com"
            ],
            body: Self.formBody(fields)
        )

        let postHTML: String
        do {
            postHTML = try await client.sendText(postReq)
        } catch {
            // Discuz 凭据错误也返回 200 + 内联错误；此处仅捕获传输 / Cloudflare 层失败。
            return .failure(.network(Self.message(from: error)))
        }

        // 连续失败会触发服务端注入验证码。
        if postHTML.contains("seccodeverify") || postHTML.contains("seccodelayer") {
            return .failure(.captchaRequired)
        }

        // 权威判定：my.php 是否仍处于游客态。
        let myHTML: String
        do {
            let myReq = try client.request(path: "my.php")
            myHTML = try await client.sendText(myReq)
        } catch {
            return .failure(.network(Self.message(from: error)))
        }
        if myHTML.contains("未登录") {
            return .failure(.loginFailed(Self.failureMessage(from: postHTML)))
        }

        // 二段校验：确认 my.php 可解析出真实登录态，避免伪造会话。
        let uid = Self.extractUID(from: myHTML)
        let resolvedName = Self.extractUsername(from: myHTML)
        guard uid != nil || resolvedName != nil else {
            return .failure(.loginFailed("登录成功但无法解析用户状态，请重试"))
        }

        guard let authCookie = HTTPCookieStorage.shared.cookies?
                .first(where: { $0.name == LoginFlowReference.AuthCookie.auth }) else {
            return .failure(.invalidResponse)
        }

        let finalUID = uid ?? 0
        let finalName = resolvedName ?? username
        let session = UserSession(uid: finalUID, username: finalName, loginTime: .now)

        // 仅 Cookie 值 + 会话快照入 Keychain，无明文密码。
        KeychainStore.shared.save(authToken: authCookie.value, username: finalName, uid: finalUID)

        return .success(session)
    }

    // MARK: - ③ 一步式便捷入口

    /// 取表单 + 提交（供无需预加载表单的调用方使用）。
    func login(username: String,
               password: String,
               questionID: Int = 0,
               answer: String = "",
               rememberMe: Bool = true) async -> Result<UserSession, AuthenticationError> {
        switch await loadLoginForm() {
        case .failure(let error):
            return .failure(error)
        case .success(let form):
            return await submit(form: form,
                                username: username,
                                password: password,
                                questionID: questionID,
                                answer: answer,
                                rememberMe: rememberMe)
        }
    }

    // MARK: - 编码

    /// GB18030（GBK 超集）编码常量，与 `HTMLDecoder` 同源。
    private static let gbkEncoding = String.Encoding(rawValue: 2147485234)

    /// 组装 `application/x-www-form-urlencoded` 请求体。
    private static func formBody(_ fields: [(key: String, value: String, gbk: Bool)]) -> Data {
        let query = fields.map { item in
            "\(percentEncode(item.key, gbk: false))=\(percentEncode(item.value, gbk: item.gbk))"
        }.joined(separator: "&")
        return Data(query.utf8)
    }

    /// 表单参数编码。
    ///
    /// **关键坑**：本论坛页面 `charset=gbk`，浏览器提交表单时按 GBK 编码字节。
    /// 中文用户名与安全提问答案若走 UTF-8，服务端会解成乱码 → 登录必然失败。
    /// 因此这两个字段必须按 GB18030 字节逐字节 percent-encode。
    private static func percentEncode(_ value: String, gbk: Bool) -> String {
        if gbk, let data = value.data(using: gbkEncoding) {
            return data.map { byte -> String in
                switch byte {
                case 0x41...0x5A, 0x61...0x7A, 0x30...0x39,  // A-Z a-z 0-9
                     0x2D, 0x5F, 0x2E, 0x7E:                 // - _ . ~
                    return String(UnicodeScalar(byte))
                default:
                    return String(format: "%%%02X", byte)
                }
            }.joined()
        }

        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - 解析辅助

    /// 尽力解析已登录用户的 UID（来自 space.php?uid= 链接）。
    static func extractUID(from html: String) -> Int? {
        let pattern = #"(?:space|userspace)\.php\?uid=(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return Int(String(html[r]))
    }

    /// 尽力解析已登录用户名（来自 "欢迎您，<name>"）。
    static func extractUsername(from html: String) -> String? {
        let pattern = #"欢迎您[，,\s]*([^<>\s]{1,40})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        let name = String(html[r]).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// 从登录失败页提取可读错误（best-effort）。
    static func failureMessage(from html: String) -> String {
        if html.contains("验证码") { return "需要输入验证码，当前版本暂不支持" }
        if html.contains("安全提问") { return "安全提问答案不正确" }
        if html.contains("密码错误") || html.contains("密码不正确") { return "密码错误" }
        if html.contains("不存在") { return "用户名不存在" }
        return "登录失败，请检查用户名和密码"
    }

    private static func message(from error: Error) -> String {
        if let ne = error as? NetworkError {
            return ne.errorDescription ?? "未知网络错误"
        }
        return error.localizedDescription
    }

    // MARK: - 密码处理

    /// 4D4Y（Discuz! 7.2 定制）要求**单 MD5**：服务端收 `hex_md5(raw_password)`。
    ///
    /// 真实账号 Python 验证结论：
    /// - 单 MD5（`hex_md5(raw)`）：登录成功，返回 `cdb_auth`。
    /// - 双 MD5（`md5(md5(raw)+count)`）：登录失败。
    ///
    /// 不做运行时算法探测——目标仅为 4D4Y，非通用 Discuz 客户端。
    /// 明文密码不离开此作用域、不打印。
    static func pwmd5(_ raw: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
