import Foundation
import CryptoKit

/// 登录数据层：复刻 Discuz! 7.2 真实登录链路（Sprint 5B 实证）。
///
/// 流程：
/// `GET logging.php?action=login` → 解析 hidden(sid / formhash / referer) →
/// `pwmd5(password)`(4D4Y: 单 MD5 `hex_md5(raw)`) → `POST logging.php?action=login&loginsubmit=yes` →
/// 捕获 `cdb_auth` Cookie → `my.php` 状态校验（含二段"可解析用户状态"校验）→ 返回 `UserSession`。
///
/// **复用** `HTTPClient`（`send` 已原生支持 POST，并经 `HTTPCookieStorage.shared` 管理 Cookie），
/// **不修改** `HTTPClient` / `Parser` / `ForumRepository`。
///
/// 安全：
/// - 明文密码仅在内存中用于计算 MD5，**绝不存储、绝不打印**。
/// - 若服务端要求验证码（seccode），返回 `.captchaRequired` 明确错误，**绝不绕过**。
final class LoginRepository {

    private let client: HTTPClient

    init(client: HTTPClient = HTTPClient()) {
        self.client = client
    }

    // MARK: - 主流程

    /// 执行一次登录尝试。
    /// - Returns: `.success(UserSession)` 或 `.failure(AuthenticationError)`。
    func login(username: String, password: String) async -> Result<UserSession, AuthenticationError> {
        // 1) GET 登录页
        let loginHTML: String
        do {
            let req = try client.request(path: LoginFlowReference.realLoginPath)
            loginHTML = try await client.sendText(req)
        } catch {
            return .failure(.network(message(from: error)))
        }

        // 2) 提前检测验证码：若登录页已注入 seccode，直接报错，绝不绕过。
        if loginHTML.contains("seccodeverify") {
            return .failure(.captchaRequired)
        }

        // 3) 解析隐藏字段
        guard let formhash = hiddenValue(html: loginHTML, name: LoginFlowReference.FormField.formhash),
              let sid = hiddenValue(html: loginHTML, name: LoginFlowReference.FormField.sid) else {
            return .failure(.invalidResponse)
        }
        let referer = hiddenValue(html: loginHTML, name: LoginFlowReference.FormField.referer) ?? ""

        // 4) pwmd5（明文密码不离开此作用域，不打印）
        let hashed = Self.pwmd5(password)

        // 5) POST 登录（x-www-form-urlencoded，复刻页面 ajaxpost 提交形态）
        var fields: [String: String] = [:]
        fields[LoginFlowReference.FormField.sid] = sid
        fields[LoginFlowReference.FormField.formhash] = formhash
        fields[LoginFlowReference.FormField.referer] = referer
        fields[LoginFlowReference.FormField.loginfield] = "username"
        fields[LoginFlowReference.FormField.username] = username
        fields[LoginFlowReference.FormField.password] = hashed
        fields[LoginFlowReference.FormField.questionid] = "0"
        fields[LoginFlowReference.FormField.answer] = ""
        fields[LoginFlowReference.FormField.cookietime] = "2592000"
        fields[LoginFlowReference.FormField.loginsubmit] = "true"

        guard let postURL = URL(string: LoginFlowReference.realLoginSubmitURL) else {
            return .failure(.invalidResponse)
        }
        let postReq = HTTPRequest(
            method: .post,
            url: postURL,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Self.urlEncoded(fields)
        )

        let postHTML: String
        do {
            postHTML = try await client.sendText(postReq)
        } catch {
            // Discuz 失败也返回 200 内联错误；此处仅捕获传输 / Cloudflare 层失败。
            return .failure(.network(message(from: error)))
        }

        // 6) POST 后再次检测验证码注入（连续失败触发）
        if postHTML.contains("seccodeverify") {
            return .failure(.captchaRequired)
        }

        // 7) my.php 状态校验（权威判定）
        let myHTML: String
        do {
            let myReq = try client.request(path: "my.php")
            myHTML = try await client.sendText(myReq)
        } catch {
            return .failure(.network(message(from: error)))
        }
        // 7a) 仍游客态 → 凭据被拒（即使 POST 返回 200 且内联失败）
        if myHTML.contains("未登录") {
            return .failure(.loginFailed(failureMessage(from: postHTML)))
        }

        // 7b) 二段校验：确认 my.php 可解析出真实登录态。
        //     仅当 uid 或 用户名任一可解析，才视为登录态生效，避免伪造会话。
        let uid = extractUID(from: myHTML)
        let resolvedName = extractUsername(from: myHTML)
        guard uid != nil || resolvedName != nil else {
            return .failure(.loginFailed("登录成功但无法解析用户状态，请重试"))
        }

        // 8) 取回鉴权 Cookie
        guard let authCookie = HTTPCookieStorage.shared.cookies?
                .first(where: { $0.name == LoginFlowReference.AuthCookie.auth }) else {
            return .failure(.invalidResponse)
        }

        // 9) 组装会话快照（解析失败兜底用输入值）
        let finalUID = uid ?? 0
        let finalName = resolvedName ?? username
        let session = UserSession(uid: finalUID, username: finalName, loginTime: .now)

        // 10) 持久化到 Keychain（仅 Cookie 值 + 快照，无明文密码）
        KeychainStore.shared.save(authToken: authCookie.value, username: finalName, uid: finalUID)

        return .success(session)
    }

    // MARK: - 辅助解析

    /// 从 HTML 中提取某个 hidden input 的 value（属性顺序无关）。
    private func hiddenValue(html: String, name: String) -> String? {
        let tagPattern = "<input[^>]*name=[\"']\(name)[\"'][^>]*>"
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

    /// 尽力解析已登录用户的 UID（来自 space.php?uid= 链接）。
    private func extractUID(from html: String) -> Int? {
        let pattern = #"(?:space|userspace)\.php\?uid=(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return Int(String(html[r]))
    }

    /// 尽力解析已登录用户名（来自 "欢迎您，<name>"）。
    private func extractUsername(from html: String) -> String? {
        let pattern = #"欢迎您[，,\s]*([^<>\s]{1,40})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        let name = String(html[r]).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// 从登录失败页提取可读错误（best-effort）。
    private func failureMessage(from html: String) -> String {
        if html.contains("验证码") { return "需要输入验证码，当前版本暂不支持" }
        if html.contains("密码错误") || html.contains("密码不正确") { return "密码错误" }
        if html.contains("不存在") { return "用户名不存在" }
        return "登录失败，请检查用户名和密码"
    }

    private func message(from error: Error) -> String {
        if let ne = error as? NetworkError {
            return ne.errorDescription ?? "未知网络错误"
        }
        return error.localizedDescription
    }

    // MARK: - 静态工具

    /// 4D4Y（Discuz! 7.2 定制）要求**单 MD5**：服务端收 `hex_md5(raw_password)`。
    ///
    /// 真实账号 Python 验证结论：
    /// - 单 MD5（`hex_md5(raw)`）：登录成功，返回 `cdb_auth`。
    /// - 双 MD5（`md5(md5(raw)+count)`）：登录失败。
    ///
    /// 不做运行时算法探测——目标仅为 4D4Y，非通用 Discuz 客户端；
    /// 以后支持其它论坛再抽象算法层。明文密码不离开此作用域、不打印。
    static func pwmd5(_ raw: String) -> String {
        md5Hex(raw)
    }

    private static func md5Hex(_ s: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func urlEncoded(_ dict: [String: String]) -> Data {
        let query = dict.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(query.utf8)
    }
}
