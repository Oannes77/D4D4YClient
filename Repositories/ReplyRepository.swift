import Foundation

// MARK: - ReplyError
/// 回复流程错误：明确区分各类失败，绝不绕过验证码 / Cloudflare。
enum ReplyError: LocalizedError, Equatable {
    case notLoggedIn          // 游客页面：会话无效
    case pageUnavailable      // Cloudflare / 拦截页：页面不可用
    case network(String)      // 网络失败
    case parseFailure(String) // 解析失败（找不到表单 / 字段）
    case captchaRequired      // 服务端要求验证码
    case submitFailed(String) // 提交失败（服务端返回错误）
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:     return "会话无效：当前为游客态，无法回复。请先登录。"
        case .pageUnavailable: return "页面不可用：站点返回拦截页（如 Cloudflare），请稍后在 App 内重试或检查网络。"
        case .network(let s):  return "网络失败：\(s)"
        case .parseFailure(let s): return "回复表单解析失败：\(s)"
        case .captchaRequired: return "需要验证码：服务器要求图形验证码，暂不支持，请使用浏览器回复。"
        case .submitFailed(let s): return "回复提交失败：\(s)"
        case .unknown(let s):  return "未知错误：\(s)"
        }
    }
}

// MARK: - ParsedReplyForm
/// 真实回复页【动态解析】得到的结果。所有字段均来自运行时抓取的 HTML，不硬编码。
struct ParsedReplyForm {
    let action: String                 // 提交地址（相对 / 绝对，运行时解析）
    let hiddenFields: [String: String] // 全部 <input type="hidden">（含 formhash / tid / 其它）
    let formhash: String               // Discuz 防 CSRF 令牌
    let tid: String                    // 主题 ID
    let messageFieldName: String       // 回复内容 textarea 的 name（通常 "message"）
    let submitField: (name: String, value: String)? // 提交按钮 name=value
}

// MARK: - ReplyRepository
/// 回复数据层。核心原则：
/// 1. 不硬编码任何 Discuz 回复 POST 参数 —— 全部在运行时从真实回复页解析；
/// 2. 依赖 HTTPCookieStorage.shared 中由 SessionManager 注入的登录 Cookie 发起请求；
/// 3. 遇到游客页 / Cloudflare 页立即中止，返回明确错误，绝不绕过。
/// 最终字段与编码方式待真实 iOS 环境验证后补充（见 docs/ReplyFlow.md）。
final class ReplyRepository {

    private let client: HTTPClient
    init(client: HTTPClient = HTTPClient()) { self.client = client }

    // MARK: 1) 加载真实回复页
    /// 使用当前 SessionManager 提供的登录 Cookie（HTTPCookieStorage.shared）请求真实回复页面。
    func loadReplyForm(tid: String) async -> Result<String, ReplyError> {
        do {
            let req = try client.request(path: "post.php?action=reply&tid=\(tid)")
            let html = try await client.sendText(req)
            // 游客页守卫：未登录时站点返回“您还未登录，无权在该版块回帖”
            if html.contains("您还未登录") || html.contains("无权在该版块回帖") {
                return .failure(.notLoggedIn)
            }
            return .success(html)
        } catch let e as NetworkError {
            // HTTPClient.send 已识别 Cloudflare 质询页并抛出，这里映射为 pageUnavailable
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: 2) 动态解析回复表单
    /// 解析：form action / hidden input / formhash / tid / textarea name / submit 字段。
    func parseReplyForm(_ html: String) -> Result<ParsedReplyForm, ReplyError> {
        guard let formHTML = Self.replyFormRegion(in: html) else {
            return .failure(.parseFailure("未找到回复表单（可能非登录态或页面异常）"))
        }
        let hidden = Self.hiddenInputs(in: formHTML)
        let action = Self.formAction(in: formHTML) ?? "post.php?action=reply"
        let formhash = hidden["formhash"] ?? ""
        let tid = hidden["tid"] ?? (Self.tidFromURL(in: html) ?? "")
        let messageFieldName = Self.textareaName(in: formHTML) ?? "message"
        let submit = Self.submitButton(in: formHTML)

        guard !formhash.isEmpty else {
            return .failure(.parseFailure("缺少 formhash（Discuz 防 CSRF 令牌）"))
        }
        return .success(ParsedReplyForm(
            action: action,
            hiddenFields: hidden,
            formhash: formhash,
            tid: tid,
            messageFieldName: messageFieldName,
            submitField: submit
        ))
    }

    // MARK: 3) 提交回复
    /// 真实提交：loadReplyForm → parseReplyForm → submit。字段全部来自动态解析，不硬编码。
    /// 编码按论坛 charset=gbk 使用 GBK 百分比编码（Sprint 7C 真实验证，详见 docs/ReplyFlow.md）。
    /// 成功判定：重新请求 viewthread，确认新增楼层（不依赖返回文案）。
    func submitReply(tid: String, message: String) async -> Result<Void, ReplyError> {
        // 1) 动态加载 + 解析（绝不跳过）
        let formRes = await loadReplyForm(tid: tid)
        let html: String
        switch formRes {
        case .success(let h): html = h
        case .failure(let err): return .failure(err)
        }
        let parsedRes = parseReplyForm(html)
        let form: ParsedReplyForm
        switch parsedRes {
        case .success(let f): form = f
        case .failure(let err): return .failure(err)
        }

        // 2) 拼装 POST 体：全部 hidden 字段 + 回复内容；submit 无 name 时不添加按钮字段
        var fields = form.hiddenFields
        fields[form.messageFieldName] = message
        if let sub = form.submitField { fields[sub.name] = sub.value }

        // 3) action 解码 HTML 实体（&amp; → &）；tid/fid 已在 action URL 中，不硬编码
        let action = form.action.replacingOccurrences(of: "&amp;", with: "&")
        guard let url = URL(string: action, relativeTo: HTTPClient.baseURL)?.absoluteURL else {
            return .failure(.parseFailure("提交地址无效: \(action)"))
        }

        // 4) GBK 百分比编码（论坛 charset=gbk）
        let body = Self.gbkFormURLEncoded(fields)

        var req = HTTPRequest(method: .post, url: url,
                              headers: ["Content-Type": "application/x-www-form-urlencoded"])
        req.body = body

        do {
            let resp = try await client.sendText(req)
            if resp.contains("您还未登录") || resp.contains("无权") {
                return .failure(.notLoggedIn)
            }
            if resp.contains("seccode") || resp.contains("验证码") {
                return .failure(.captchaRequired)
            }
            // 回显仅作辅助；最终以楼层验证为准
            if resp.contains("抱歉") || resp.contains("失败") || resp.contains("错误") {
                Log.network.warning("提交回显含失败字样，将以楼层验证为准")
            }
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }

        // 5) 成功判定：重新请求 viewthread，确认新增楼层存在
        return await verifyPosted(tid: tid, message: message)
    }

    /// 提交后重新拉取帖子，确认回复内容真实出现（不依赖返回文案、不本地伪造）。
    /// 新回复落在帖子末页，故请求末页（Discuz 将越界 page 钳制到末页，已在 4D4Y 验证）。
    private func verifyPosted(tid: String, message: String) async -> Result<Void, ReplyError> {
        do {
            let req = try client.request(path: "viewthread.php?tid=\(tid)&page=9999")
            let vt = try await client.sendText(req)
            if vt.contains("您还未登录") { return .failure(.notLoggedIn) }
            if vt.contains(message) { return .success(()) }
            return .failure(.submitFailed("回复未出现在帖子（可能编码错位或服务端未即时生效）"))
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: - 解析辅助（纯正则，自包含；如需更稳健可整体替换为 SwiftSoup）
    private static func replyFormRegion(in html: String) -> String? {
        let pattern = #"<form[^>]*>.*?</form>"#
        guard let re = try? NSRegularExpression(pattern: pattern,
                    options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return nil }
        let forms = re.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var fallback: String?
        for f in forms {
            let region = (html as NSString).substring(with: f.range)
            // 优先：含回复内容 textarea（name="message"）的表单
            if region.range(of: "name=[\"']message[\"']", options: .regularExpression) != nil {
                return region
            }
            // 兜底：含 post.php 且有 textarea 的表单
            if region.lowercased().contains("post.php")
               && region.range(of: "<textarea", options: .caseInsensitive) != nil {
                fallback = fallback ?? region
            }
        }
        return fallback
    }

    private static func formAction(in formHTML: String) -> String? {
        let m = Self.first(pattern: #"<form[^>]*\baction=["']([^"']*)["']"#, in: formHTML,
                           options: [.caseInsensitive])
        return m.flatMap { (formHTML as NSString).substring(with: $0.range(at: 1)) }
    }

    private static func hiddenInputs(in formHTML: String) -> [String: String] {
        var dict: [String: String] = [:]
        let m = Self.all(pattern: #"<input[^>]*type=["']hidden["'][^>]*>"#, in: formHTML)
        for r in m {
            let tag = (formHTML as NSString).substring(with: r.range)
            guard let name = Self.attr("name", in: tag),
                  let value = Self.attr("value", in: tag) else { continue }
            dict[name] = value
        }
        return dict
    }

    private static func textareaName(in formHTML: String) -> String? {
        let m = Self.first(pattern: #"<textarea[^>]*\bname=["']([^"']*)["']"#, in: formHTML,
                           options: [.caseInsensitive])
        return m.flatMap { (formHTML as NSString).substring(with: $0.range(at: 1)) }
    }

    private static func submitButton(in formHTML: String) -> (name: String, value: String)? {
        let m = Self.first(pattern: #"<(?:input|button)[^>]*type=["']submit["'][^>]*>"#,
                           in: formHTML, options: [.caseInsensitive])
        guard let r = m else { return nil }
        let tag = (formHTML as NSString).substring(with: r.range)
        guard let name = Self.attr("name", in: tag) else { return nil }
        let value = Self.attr("value", in: tag) ?? ""
        return (name, value)
    }

    private static func tidFromURL(in html: String) -> String? {
        let m = Self.first(pattern: #"tid\s*=\s*parseInt\(['"]?(\d+)"#, in: html)
        return m.flatMap { (html as NSString).substring(with: $0.range(at: 1)) }
    }

    /// 属性取值：兼容 name="x" 与 name='x'。
    private static func attr(_ name: String, in tag: String) -> String? {
        let p = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"=["']([^"']*)["']"#
        guard let r = Self.first(pattern: p, in: tag, options: []) else { return nil }
        return (tag as NSString).substring(with: r.range(at: 1))
    }

    private static func first(pattern: String, in text: String,
                              options: NSRegularExpression.Options = []) -> NSTextCheckingResult? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func all(pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let re = try? NSRegularExpression(pattern: pattern,
                    options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// GBK（GB18030 超集）百分比编码：论坛 charset=gbk，表单按 GBK 字节逐字节 %XX 编码。
    /// 经验证（Sprint 7C）UTF-8 在含中文时服务端会存为乱码，GBK 正确。
    private static func gbkFormURLEncoded(_ params: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_.~"))
        let segs = params.map { "\(gbkPercent($0.key, allowed: allowed))=\(gbkPercent($0.value, allowed: allowed))" }
        return segs.joined(separator: "&").data(using: .ascii) ?? Data()
    }

    private static func gbkPercent(_ s: String, allowed: CharacterSet) -> String {
        // GB 18030（GBK 超集）。部分 SDK 的 String.Encoding 未暴露 .gb_18030_2000 静态成员，
        // 故用 rawValue 构造：2147485234 = kCFStringEncodingGB_18030_2000。
        let gbk = String.Encoding(rawValue: 2147485234)
        guard let data = s.data(using: gbk) else {
            return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        }
        return data.map { String(format: "%%%02X", $0) }.joined()
    }
}
