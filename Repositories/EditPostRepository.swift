import Foundation

/// 编辑帖子表单（真实编辑页 `post.php?action=edit…` 的运行时解析结果）。
/// 所有字段均来自运行时抓取的 HTML，不硬编码。
struct ParsedEditForm {
    /// 提交地址（站点原样，含 `&action=edit&editsubmit=yes`）。
    let action: String
    /// 全部 `<input type="hidden">`（formhash / fid / tid / pid / page / posttime / iconid …）。
    let hiddenFields: [String: String]
    /// Discuz 防 CSRF 令牌。
    let formhash: String
    /// 预填标题（`input[name=subject]`）；回复楼没有该字段时为空串。
    let subject: String
    /// 正文 textarea 的 name（通常 `message`）。
    let messageFieldName: String
    /// 预填正文（原帖内容，用于回显）。
    let messageText: String
    /// 提交按钮 name=value（编辑页是 `editsubmit=true`）。
    let submitField: (name: String, value: String)?
}

/// 编辑自己的帖子数据层（`post.php?action=edit…`）。原则与发帖 / 回复完全一致：
/// 1. **不硬编码任何 POST 参数** —— 全部在运行时从真实编辑页解析；
/// 2. 依赖 `HTTPCookieStorage.shared` 中由 SessionManager 注入的登录 Cookie；
/// 3. 提交后**回读编辑页确认**（服务器回读是唯一判据），确认不了返回失败，绝不谎报成功；
/// 4. 遇到游客页 / Cloudflare 页立即中止，返回明确错误，绝不绕过；
/// 5. 只请求**本站范围内**的地址（`HTTPClient.isAllowedForumPath`），拒绝跨域 / 逃逸。
///
/// ⚠️ 「删除自己的帖子」**当前站点不给入口**：编辑页与帖子浏览页均无删除控件
/// （见 `docs/Sprint23-Changelog.md`），故本层只实现「编辑」，不伪造删除。
final class EditPostRepository {

    private let client: HTTPClient
    init(client: HTTPClient = HTTPClient()) { self.client = client }

    // MARK: 1) 加载编辑页
    /// - Parameter path: 站点原样的编辑地址（来自帖子楼层 `a.editpost` 的 href）。
    func loadEditForm(path: String) async -> Result<String, PostError> {
        guard HTTPClient.isAllowedForumPath(path) else {
            return .failure(.parseFailure("编辑地址不在本站范围内：\(path)"))
        }
        do {
            let req = try client.request(path: path)
            let html = try await client.sendText(req)
            if html.contains("您还未登录") || html.contains("无权") {
                return .failure(.notLoggedIn)
            }
            return .success(html)
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: 2) 解析编辑表单
    func parseEditForm(_ html: String) -> Result<ParsedEditForm, PostError> {
        guard let region = DiscuzFormParser.formRegion(in: html, requiring: #"name=["']message["']"#) else {
            return .failure(.parseFailure("未找到编辑表单（可能非登录态或页面异常）"))
        }
        let form = DiscuzFormParser.parse(region)
        guard let formhash = form.formhash, !formhash.isEmpty else {
            return .failure(.parseFailure("缺少 formhash（Discuz 防 CSRF 令牌）"))
        }
        return .success(ParsedEditForm(
            action: form.action,
            hiddenFields: form.hiddenFields,
            formhash: formhash,
            subject: Self.inputValue(name: "subject", in: region) ?? "",
            messageFieldName: form.messageFieldName,
            messageText: Self.textareaValue(name: form.messageFieldName, in: region) ?? "",
            submitField: form.submitField
        ))
    }

    // MARK: 3) 提交编辑
    /// 提交编辑：loadEditForm → parseEditForm → GBK 表单 POST → **回读编辑页确认**。
    ///
    /// 只提交**标题 + 正文**（站点的编辑页正是这两个字段）。不自行拼 `typeid`：
    /// 该板块的分类是 JS 菜单，页面 `<select>` 为空值时不覆盖它，避免张冠李戴改掉分类。
    func submitEdit(path: String, subject: String, message: String) async -> Result<Void, PostError> {
        let formRes = await loadEditForm(path: path)
        let html: String
        switch formRes {
        case .success(let h): html = h
        case .failure(let error): return .failure(error)
        }

        let parsedRes = parseEditForm(html)
        let form: ParsedEditForm
        switch parsedRes {
        case .success(let f): form = f
        case .failure(let error): return .failure(error)
        }

        // 拼装字段：全部 hidden + 标题 + 正文 + 提交按钮（与页面行为一致）。
        var fields = form.hiddenFields
        fields["subject"] = subject
        fields[form.messageFieldName] = message
        if let s = form.submitField {
            fields[s.name] = s.value
        } else {
            fields["editsubmit"] = "true"      // 兜底：Discuz 7.2 编辑按钮名
        }

        guard HTTPClient.isAllowedForumPath(form.action) else {
            return .failure(.parseFailure("提交地址不在本站范围内：\(form.action)"))
        }
        let baseRequest: HTTPRequest
        do {
            baseRequest = try client.request(path: form.action)
        } catch {
            return .failure(.parseFailure("提交地址无效: \(form.action)"))
        }
        var req = baseRequest
        req.method = .post
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.headers["Referer"] = HTTPClient.baseURL.appendingPathComponent("post.php").absoluteString
        req.body = DiscuzFormParser.gbkFormURLEncoded(fields)

        do {
            let resp = try await client.sendText(req)
            if resp.contains("您还未登录") || resp.contains("无权") {
                return .failure(.notLoggedIn)
            }
            if resp.contains("seccode") || resp.contains("验证码") {
                return .failure(.captchaRequired)
            }
            if resp.contains("抱歉") || resp.contains("错误") || resp.contains("失败") {
                return .failure(.submitFailed(Self.brief(resp)))
            }
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }

        // 回读编辑页：确认新内容真的落库（服务器回读是唯一判据）。
        return await verifyEdited(path: path, message: message, subject: subject)
    }

    /// 回读编辑页，确认新的正文（或标题）已生效。
    private func verifyEdited(path: String, message: String, subject: String) async -> Result<Void, PostError> {
        let needle = Self.verifyNeedle(message: message, subject: subject)
        guard !needle.isEmpty else {
            return .failure(.submitFailed("编辑内容为空，无法回读确认"))
        }
        switch await loadEditForm(path: path) {
        case .success(let html):
            return html.contains(needle)
                ? .success(())
                : .failure(.submitFailed("编辑后回读编辑页未看到新内容（可能未生效或需审核）"))
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - 辅助

    /// 回读校验用的特征串：优先正文首行（前 24 字），为空时退回标题（前 24 字）。
    private static func verifyNeedle(message: String, subject: String) -> String {
        let firstLine = message.split(separator: "\n").first.map(String.init) ?? message
        let m = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = m.isEmpty ? subject.trimmingCharacters(in: .whitespacesAndNewlines) : m
        return String(candidate.prefix(24))
    }

    /// 取 `<input name="subject" … value="…">` 的 value。
    private static func inputValue(name: String, in region: String) -> String? {
        let esc = NSRegularExpression.escapedPattern(for: name)
        let tagPattern = #"<input[^>]*\bname=["']"# + esc + #"["'][^>]*>"#
        guard let tag = firstMatch(tagPattern, in: region) else { return nil }
        return firstCapture(#"\bvalue=["']([^"']*)["']"#, in: tag)
    }

    /// 取 `<textarea name="message" …>CONTENT</textarea>` 的内容（`[\s\S]` 兼容跨行）。
    private static func textareaValue(name: String, in region: String) -> String? {
        let esc = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"<textarea[^>]*\bname=["']"# + esc + #"["'][^>]*>([\s\S]*?)</textarea>"#
        return firstCapture(pattern, in: region)
    }

    private static func firstMatch(_ pattern: String, in text: String,
                                   options: NSRegularExpression.Options = [.caseInsensitive]) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = re.firstMatch(in: text, range: range), let r = Range(m.range, in: text) else { return nil }
        return String(text[r])
    }

    private static func firstCapture(_ pattern: String, in text: String,
                                     options: NSRegularExpression.Options = [.caseInsensitive]) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// 失败提示的简短摘要（去掉脚本 / 标签后的前 80 字）。
    private static func brief(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<script.*?</script>"#, with: " ",
                                             options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "服务端未返回明确原因" : String(text.prefix(80))
    }
}
