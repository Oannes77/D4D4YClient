import Foundation

/// Discuz 表单通用解析与提交编码工具（回复 / 发帖共用）。
///
/// 原则与 `ReplyRepository` 一致：**不硬编码任何 POST 参数**，
/// 全部在运行时从真实页面 HTML 动态解析（action / hidden / textarea / submit）。
enum DiscuzFormParser {

    /// 运行时解析出的表单。
    struct Form {
        /// 提交地址（相对或绝对，原样保留）
        let action: String
        /// 全部 <input type="hidden">
        let hiddenFields: [String: String]
        /// 表单内所有 textarea 的 name（按出现顺序）
        let textareaNames: [String]
        /// 提交按钮 name=value（无 name 时为 nil）
        let submitField: (name: String, value: String)?
        /// 表单内 `<input type="file">` 的 name（按出现顺序）。附件上传用。
        let fileFieldNames: [String]
        /// 表单是否声明为 `multipart/form-data`。
        let isMultipart: Bool

        var formhash: String? { hiddenFields["formhash"] }
        /// 正文 textarea 名（通常为 message；找不到时回退第一个 textarea）
        var messageFieldName: String {
            textareaNames.first(where: { $0 == "message" }) ?? textareaNames.first ?? "message"
        }
    }

    // MARK: - 表单定位

    /// 在整页 HTML 中定位表单区域。
    /// - Parameter marker: 该表单必须包含的正则片段（如 `name=["']message["']`）；nil 表示取第一个表单。
    static func formRegion(in html: String, requiring marker: String? = nil) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: #"<form[^>]*>.*?</form>"#,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else { return nil }
        let matches = re.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var fallback: String?
        for m in matches {
            let region = (html as NSString).substring(with: m.range)
            guard !region.isEmpty else { continue }
            if let marker {
                if region.range(of: marker, options: .regularExpression) != nil { return region }
            } else {
                return region
            }
            // 兜底：含 textarea 的表单
            if fallback == nil,
               region.range(of: "<textarea", options: .caseInsensitive) != nil {
                fallback = region
            }
        }
        return fallback
    }

    // MARK: - 字段解析

    static func parse(_ region: String) -> Form {
        let action = first(#"<form[^>]*\baction=["']([^"']*)["']"#, in: region)
            ?? "post.php"
        let cleanedAction = action.replacingOccurrences(of: "&amp;", with: "&")
        return Form(
            action: cleanedAction,
            hiddenFields: hiddenInputs(in: region),
            textareaNames: textareaNames(in: region),
            submitField: submitButton(in: region),
            fileFieldNames: fileInputNames(in: region),
            isMultipart: region.range(of: #"enctype\s*=\s*["']?multipart/form-data"#,
                                      options: [.regularExpression, .caseInsensitive]) != nil
        )
    }

    private static func hiddenInputs(in region: String) -> [String: String] {
        var dict: [String: String] = [:]
        for r in all(#"<input[^>]*type=["']hidden["'][^>]*>"#, in: region) {
            let tag = (region as NSString).substring(with: r.range)
            guard let name = attr("name", in: tag), let value = attr("value", in: tag) else { continue }
            dict[name] = value
        }
        return dict
    }

    private static func textareaNames(in region: String) -> [String] {
        all(#"<textarea[^>]*\bname=["']([^"']*)["']"#, in: region).compactMap {
            (region as NSString).substring(with: $0.range(at: 1))
        }
    }

    /// 表单内 `<input type="file">` 的 name。
    ///
    /// Discuz! 的发帖页可能把附件区交给 JS（SWFUpload）处理，此时解析不到 file 域；
    /// 调用方会退回 `attach[]` 这一 Discuz 惯用字段名再试。
    private static func fileInputNames(in region: String) -> [String] {
        all(#"<input[^>]*type=["']file["'][^>]*>"#, in: region).compactMap { m in
            let tag = (region as NSString).substring(with: m.range)
            return attr("name", in: tag)
        }
    }

    /// 附件上传密钥（Discuz SWFUpload **两步协议**第一步要用）。
    ///
    /// 发帖页的 `form#imgattachform`（PC 模板）里有两个 hidden：`uid` 与 `hash`。
    /// 它们和文件一起 POST 到
    /// `misc.php?action=swfupload&operation=upload&simple=1&type=image`，
    /// 响应体是纯文本 `DISCUZUPLOAD|0|<aid>`，第 3 段即附件 ID。
    ///
    /// 解析不到时返回 nil —— 调用方据此**如实报告**「拿不到上传凭据」，
    /// 不伪造 aid、不假装上传成功。
    static func attachmentUploadKeys(in html: String) -> (uid: String, hash: String)? {
        // 优先限定在附件表单区域内，避免匹配到页面上其它 uid/hash 域。
        let region = formRegion(in: html, requiring: #"id=["']imgattachform["']"#)
            ?? formRegion(in: html, requiring: #"swfupload|attachment\.php"#)
            ?? html
        let hidden = hiddenInputs(in: region)
        guard let uid = hidden["uid"], let hash = hidden["hash"] else { return nil }
        return (uid, hash)
    }

    private static func submitButton(in region: String) -> (name: String, value: String)? {
        guard let m = all(#"<(?:input|button)[^>]*type=["']submit["'][^>]*>"#, in: region).first else { return nil }
        let tag = (region as NSString).substring(with: m.range)
        guard let name = attr("name", in: tag) else { return nil }
        return (name, attr("value", in: tag) ?? "")
    }

    // MARK: - 提交编码

    /// GBK（GB18030 超集）百分比编码：论坛 charset=gbk，表单按 GBK 字节逐字节 %XX 编码。
    /// 经验证（Sprint 7C）UTF-8 在含中文时服务端会存为乱码，GBK 正确。
    static func gbkFormURLEncoded(_ params: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_.~"))
        let segs = params.map {
            "\(gbkPercent($0.key, allowed: allowed))=\(gbkPercent($0.value, allowed: allowed))"
        }
        return segs.joined(separator: "&").data(using: .ascii) ?? Data()
    }

    /// multipart/form-data 里的一个文件。
    struct MultipartFile {
        let fieldName: String
        let fileName: String
        let mimeType: String
        let data: Data
    }

    /// 生成一个 multipart 边界串。
    static func makeBoundary() -> String {
        "----D4D4YClientBoundary" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    /// 构造 multipart/form-data 请求体：文本字段（**GBK 编码**）+ 文件。
    ///
    /// 为什么文本字段用 GBK：论坛 `charset=gbk`，UTF-8 提交中文会在服务端存成乱码（Sprint 7C 已验证）。
    /// 文件内容按二进制原样写入，不做任何编码转换。
    static func multipartBody(boundary: String,
                              fields: [String: String],
                              files: [MultipartFile]) -> Data {
        let gbk = String.Encoding(rawValue: 2147485234)
        var body = Data()

        func appendASCII(_ text: String) {
            body.append(text.data(using: .utf8) ?? Data())
        }

        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            appendASCII("--\(boundary)\r\n")
            appendASCII("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append(value.data(using: gbk) ?? value.data(using: .utf8) ?? Data())
            appendASCII("\r\n")
        }

        for file in files {
            appendASCII("--\(boundary)\r\n")
            // 文件名同样用 GBK，避免中文文件名在服务端变乱码。
            let nameData = file.fileName.data(using: gbk) ?? file.fileName.data(using: .utf8) ?? Data()
            appendASCII("Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"")
            body.append(nameData)
            appendASCII("\"\r\n")
            appendASCII("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            appendASCII("\r\n")
        }

        appendASCII("--\(boundary)--\r\n")
        return body
    }

    static func gbkPercent(_ s: String, allowed: CharacterSet) -> String {
        // GB 18030（GBK 超集）：rawValue 2147485234 = kCFStringEncodingGB_18030_2000
        let gbk = String.Encoding(rawValue: 2147485234)
        guard let data = s.data(using: gbk) else {
            return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        }
        return data.map { String(format: "%%%02X", $0) }.joined()
    }

    // MARK: - 正则辅助

    private static func first(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let range = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func all(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let re = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func attr(_ name: String, in tag: String) -> String? {
        let p = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"=["']([^"']*)["']"#
        return first(p, in: tag)
    }
}
