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
    /// 附件上传（SWFUpload 第一步）失败 —— 此时**不会发出帖子**，如实报告原因。
    case attachmentUploadFailed(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:     return "会话无效：当前为游客态，无法发帖。请先登录。"
        case .pageUnavailable: return "页面不可用：站点返回拦截页（如 Cloudflare），请稍后在 App 内重试。"
        case .network(let s):  return "网络失败：\(s)"
        case .parseFailure(let s): return "发帖表单解析失败：\(s)"
        case .captchaRequired: return "需要验证码：服务器要求图形验证码，暂不支持，请使用浏览器发帖。"
        case .submitFailed(let s): return "发帖提交失败：\(s)"
        case .attachmentUploadFailed(let s): return "附件上传失败：\(s)（帖子未发出）"
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
/// ⚠️ 站点用的是 Discuz 经典 **SWFUpload 两步协议**，**不是**「文件与正文塞进同一个请求」：
/// 1. 先把文件 POST 到 `misc.php?action=swfupload&operation=upload&simple=1&type=…`，
///    换回附件 ID（`aid`）；
/// 2. 再用**普通 GBK 表单**发帖，正文尾部以 `[attachimg]aid[/attachimg]`（图片）
///    或 `[attach]aid[/attach]`（其它文件）引用该 aid，
///    并为每个 aid 带一条 `attachnew[<aid>][description]=`。
///
/// 该协议取自生产可用的参考实现（`github.com/webrules/4d4y`），
/// 详见 `docs/RefProject.md` §4。
struct PostAttachment {
    let fileName: String
    let mimeType: String
    let data: Data

    /// 是否图片：决定 SWFUpload 的 `type=` 参数与正文里的 BBcode 标签。
    var isImage: Bool { mimeType.lowercased().hasPrefix("image/") }
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
                         attachments: [PostAttachment] = [],
                         typeID: Int? = nil) async -> Result<PostedThread, PostError> {
        // 1) 动态加载 + 解析（绝不跳过）
        let formResult = await loadNewThreadForm(fid: fid)
        switch formResult {
        case .success(let html):
            return await submit(withHTML: html, fid: fid, subject: subject,
                                message: message, attachments: attachments, typeID: typeID)
        case .failure(let error):
            return .failure(error)
        }
    }

    private func submit(withHTML html: String, fid: Int,
                        subject: String, message: String,
                        attachments: [PostAttachment],
                        typeID: Int?) async -> Result<PostedThread, PostError> {
        guard let region = DiscuzFormParser.formRegion(in: html, requiring: #"name=["']message["']"#) else {
            return .failure(.parseFailure("未找到发帖表单（可能非登录态或页面异常）"))
        }
        let form = DiscuzFormParser.parse(region)
        guard let formhash = form.formhash, !formhash.isEmpty else {
            return .failure(.parseFailure("缺少 formhash（Discuz 防 CSRF 令牌）"))
        }

        // 2) 附件：**先上传换 aid**（SWFUpload 两步协议第一步）。
        //    任何一个附件失败即整体中止 —— 不发出「正文与附件不符」的半个帖子。
        var uploaded: [(aid: Int, isImage: Bool)] = []
        if !attachments.isEmpty {
            guard let keys = DiscuzFormParser.attachmentUploadKeys(in: html) else {
                return .failure(.attachmentUploadFailed(
                    "未能在发帖页解析到上传凭据（uid / hash）；可能该板块不允许附件，或页面结构不同"))
            }
            for file in attachments {
                switch await uploadAttachment(file, keys: keys) {
                case .success(let aid):  uploaded.append((aid, file.isImage))
                case .failure(let error): return .failure(error)
                }
            }
        }

        // 3) 拼装字段：全部 hidden + 标题 + 正文（尾部追加附件引用）+ 提交按钮
        var fields = form.hiddenFields
        fields["subject"] = subject

        // 主题分类（`typeid`）：字段名取自参考实现 `docs/RefProject.md` §4 的表格
        // （站点发帖表单里就是 `typeid`）。用户没选就不覆盖页面自带的值，不猜。
        if let typeID { fields["typeid"] = String(typeID) }

        var body = message
        if !uploaded.isEmpty {
            let refs = uploaded.map { $0.isImage ? "[attachimg]\($0.aid)[/attachimg]"
                                                 : "[attach]\($0.aid)[/attach]" }
            body += "\n" + refs.joined(separator: "\n") + "\n"
            for item in uploaded { fields["attachnew[\(item.aid)][description]"] = "" }
        }
        fields[form.messageFieldName] = body

        if let s = form.submitField {
            fields[s.name] = s.value
        } else {
            fields["topicsubmit"] = "true"     // 兜底：Discuz 7.2 发帖按钮名
        }

        // 4) POST：**一律 GBK 表单**。附件已在第一步单独上传，这里不再走 multipart。
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

    // MARK: 3) 附件上传（SWFUpload 两步协议 · 第一步）
    /// 把单个文件上传到 Discuz 的 SWFUpload 端点，换回附件 ID。
    ///
    /// - 端点：`misc.php?action=swfupload&operation=upload&simple=1&type=image|attach`
    /// - 字段：`uid` / `hash`（取自发帖页 `form#imgattachform`）+ `Filedata`（**原始文件名**）
    /// - 响应：纯文本 `DISCUZUPLOAD|0|<aid>`
    ///
    /// 任何异常都返回明确错误，**绝不伪造 aid**。
    private func uploadAttachment(_ file: PostAttachment,
                                  keys: (uid: String, hash: String)) async -> Result<Int, PostError> {
        let boundary = DiscuzFormParser.makeBoundary()
        let type = file.isImage ? "image" : "attach"
        let path = "misc.php?action=swfupload&operation=upload&simple=1&type=\(type)"
        do {
            var req = try client.request(path: path)
            req.method = .post
            req.headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
            req.headers["Referer"] = HTTPClient.baseURL.appendingPathComponent("post.php").absoluteString
            req.body = DiscuzFormParser.multipartBody(
                boundary: boundary,
                fields: ["uid": keys.uid, "hash": keys.hash],
                files: [DiscuzFormParser.MultipartFile(fieldName: "Filedata",
                                                       fileName: file.fileName,
                                                       mimeType: file.mimeType,
                                                       data: file.data)]
            )
            let resp = try await client.sendText(req)
            if let aid = Self.uploadAid(in: resp) { return .success(aid) }
            return .failure(.attachmentUploadFailed(
                "\(file.fileName)：服务端未返回附件 ID（\(Self.brief(resp))）"))
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    /// 解析 SWFUpload 响应：`DISCUZUPLOAD|0|<aid>` → `aid`。
    ///
    /// 首段不是 `DISCUZUPLOAD`、或状态位不是 `0`（表示上传失败）时返回 nil。
    static func uploadAid(in response: String) -> Int? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              parts[0].trimmingCharacters(in: .whitespaces) == "DISCUZUPLOAD",
              parts[1].trimmingCharacters(in: .whitespaces) == "0" else { return nil }
        return Int(parts[2].trimmingCharacters(in: .whitespaces))
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
