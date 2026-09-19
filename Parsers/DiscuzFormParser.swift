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
            submitField: submitButton(in: region)
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

    private static func submitButton(in region: String) -> (name: String, value: String)? {
        guard let r = first(#"<(?:input|button)[^>]*type=["']submit["'][^>]*>"#, in: region) else { return nil }
        let tag = (region as NSString).substring(with: r.range)
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
