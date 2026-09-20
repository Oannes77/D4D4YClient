import Foundation

// MARK: - PostError
/// 发帖流程错误：与回复流程一致，明确区分各类失败，绝不绕过验证码 / Cloudflare。
enum PostError: LocalizedError, Equatable {
    case notLoggedIn
    case pageUnavailable
    case network(String)
    case parseFailure(String)
    case captchaRequired
    case submitFailed(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:     return "会话无效：当前为游客态，无法发帖。请先登录。"
        case .pageUnavailable: return "页面不可用：站点返回拦截页（如 Cloudflare），请稍后在 App 内重试。"
        case .network(let s):  return "网络失败：\(s)"
        case .parseFailure(let s): return "发帖表单解析失败：\(s)"
        case .captchaRequired: return "需要验证码：服务器要求图形验证码，暂不支持，请使用浏览器发帖。"
        case .submitFailed(let s): return "发帖提交失败：\(s)"
        case .unknown(let s):  return "未知错误：\(s)"
        }
    }
}

/// 发帖结果：成功时给出新主题 tid（服务端未回传时为 nil）。
struct PostedThread: Hashable {
    let tid: Int?
}

/// 待随帖上传的附件（图片或普通文件）。
///
/// 附件走 `multipart/form-data` 与正文**一次性提交**：Discuz 的发帖页本身就是一个
/// 可带文件的表单，因此不需要额外的两步上传流程。
struct PostAttachment {
    let fileName: String
    let mimeType: String
    let data: Data
}

// MARK: - PostRepository
/// 发帖数据层（newthread）。原则与回复一致：
/// 1. 不硬编码 POST 参数 —— 全部运行时从真实发帖页解析；
/// 2. 使用 `HTTPCookieStorage.shared` 中由 SessionManager 注入的登录 Cookie；
/// 3. 遇到游客页 / Cloudflare 页立即中止，返回明确错误，绝不绕过。
final class PostRepository {

    private let client: HTTPClient
    init(client: HTTPClient = HTTPClient()) { self.client = client }

    // MARK: 1) 加载真实发帖页
    func loadNewThreadForm(fid: Int) async -> Result<String, PostError> {
        do {
            let req = try client.request(path: "post.php?action=newthread&fid=\(fid)")
            let html = try await client.sendText(req)
            if html.contains("您还未登录") || html.contains("无权") || html.contains("抱歉") {
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

    // MARK: 2) 提交新帖
    /// - Parameters:
    ///   - fid: 目标板块。
    ///   - subject: 标题；为空时由调用方先行补全（Discuz 多数版块禁止空标题）。
    ///   - message: 正文（已含自动附加的占位符）。
    func submitNewThread(fid: Int, subject: String, message: String,
                         attachments: [PostAttachment] = []) async -> Result<PostedThread, PostError> {
        // 1) 动态加载 + 解析（绝不跳过）
        let formResult = await loadNewThreadForm(fid: fid)
        switch formResult {
        case .success(let html):
            return await submit(withHTML: html, fid: fid, subject: subject,
                                message: message, attachments: attachments)
        case .failure(let error):
            return .failure(error)
        }
    }

    private func submit(withHTML html: String, fid: Int,
                        subject: String, message: String,
                        attachments: [PostAttachment]) async -> Result<PostedThread, PostError> {
        guard let region = DiscuzFormParser.formRegion(in: html, requiring: #"name=["']message["']"#) else {
            return .failure(.parseFailure("未找到发帖表单（可能非登录态或页面异常）"))
        }
        let form = DiscuzFormParser.parse(region)
        guard let formhash = form.formhash, !formhash.isEmpty else {
            return .failure(.parseFailure("缺少 formhash（Discuz 防 CSRF 令牌）"))
        }

        // 2) 拼装字段：全部 hidden + 标题 + 正文 + 提交按钮
        var fields = form.hiddenFields
        fields["subject"] = subject
        fields[form.messageFieldName] = message
        if let s = form.submitField {
            fields[s.name] = s.value
        } else {
            fields["topicsubmit"] = "true"     // 兜底：Discuz 7.2 发帖按钮名
        }

        // 3) POST（带 Referer，模拟站内提交）
        //    无附件 → GBK 表单编码；有附件 → multipart/form-data（字段同样 GBK 编码）。
        let baseRequest: HTTPRequest
        do {
            baseRequest = try client.request(path: form.action)
        } catch {
            return .failure(.parseFailure("提交地址无效: \(form.action)"))
        }
        var req = baseRequest
        req.method = .post
        req.headers["Referer"] = HTTPClient.baseURL.appendingPathComponent("post.php").absoluteString

        if attachments.isEmpty {
            req.headers["Content-Type"] = "application/x-www-form-urlencoded"
            req.body = DiscuzFormParser.gbkFormURLEncoded(fields)
        } else {
            let boundary = DiscuzFormParser.makeBoundary()
            // 附件文件域字段名：优先用运行时解析到的；解析不到（Discuz 交给 JS 上传）时退回惯用名。
            let fieldName = form.fileFieldNames.first ?? "attach[]"
            let files = attachments.map {
                DiscuzFormParser.MultipartFile(fieldName: fieldName,
                                               fileName: $0.fileName,
                                               mimeType: $0.mimeType,
                                               data: $0.data)
            }
            req.headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
            req.body = DiscuzFormParser.multipartBody(boundary: boundary, fields: fields, files: files)
        }

        do {
            let resp = try await client.sendText(req)
            if resp.contains("您还未登录") || resp.contains("无权") {
                return .failure(.notLoggedIn)
            }
            if resp.contains("seccode") || resp.contains("验证码") {
                return .failure(.captchaRequired)
            }
            if let tid = Self.tid(in: resp) {
                return .success(PostedThread(tid: tid))
            }
            if resp.contains("抱歉") || resp.contains("错误") || resp.contains("失败") {
                return .failure(.submitFailed(Self.brief(resp)))
            }
            // 回显无明确信号：复查板块第一页是否出现该主题（不本地伪造成功）
            return await verify(fid: fid, subject: subject)
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    /// 复查：重新拉取板块第一页，确认标题真实出现。
    private func verify(fid: Int, subject: String) async -> Result<PostedThread, PostError> {
        guard !subject.isEmpty else {
            return .failure(.submitFailed("服务端未返回主题地址，且标题为空无法复查（请填写标题后重试）"))
        }
        do {
            let req = try client.request(path: "forumdisplay.php?fid=\(fid)")
            let html = try await client.sendText(req)
            if html.contains(subject) { return .success(PostedThread(tid: nil)) }
            return .failure(.submitFailed("发帖后未在板块列表找到该标题（可能未生效或需审核）"))
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: - 辅助

    /// 从响应中提取新主题 tid（Discuz 发布成功后回显/跳转到 viewthread.php?tid=NNN）。
    static func tid(in html: String) -> Int? {
        guard let range = html.range(of: #"viewthread\.php\?tid=(\d+)"#, options: .regularExpression),
              let digits = html[range].split(separator: "=").last else { return nil }
        return Int(digits)
    }

    /// 提取失败提示的简短摘要（去掉脚本/标签后的前 80 字）。
    static func brief(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<script.*?</script>"#, with: " ",
                                             options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "服务端未返回明确原因" : String(text.prefix(80))
    }
}
