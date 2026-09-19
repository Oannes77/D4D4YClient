import Foundation

/// 登录页（`logging.php?action=login`）解析器。
///
/// 只做**读取与结构提取**，不发起任何网络请求、不提交任何表单。
/// 解析失败时安全提问回退到 Discuz 7.2 标准列表，不会阻塞登录流程。
enum LoginFormParser {

    /// 解析登录页 HTML 为可提交的表单快照。
    /// - Returns: 取不到 `formhash` 时返回 nil（视为页面结构异常）。
    static func parse(html: String) -> LoginForm? {
        guard let formhash = hiddenValue(html: html, name: "formhash") else { return nil }

        let sid = hiddenValue(html: html, name: "sid") ?? ""
        let referer = hiddenValue(html: html, name: "referer") ?? ""
        let questions = parseQuestions(html: html)

        // 验证码：默认不出现，连续失败后服务端注入。只识别，绝不绕过。
        let requiresCaptcha = html.contains("seccodeverify") || html.contains("seccodelayer")

        return LoginForm(sid: sid,
                         formhash: formhash,
                         referer: referer,
                         questions: questions,
                         requiresCaptcha: requiresCaptcha)
    }

    // MARK: - 隐藏字段

    /// 从 HTML 中提取某个 hidden input 的 value（属性顺序无关）。
    static func hiddenValue(html: String, name: String) -> String? {
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

    // MARK: - 安全提问

    /// 解析 `<select name="questionid">` 内的全部 `<option value="N">文本</option>`。
    /// 解析不到则返回标准兜底列表。
    private static func parseQuestions(html: String) -> [SecurityQuestion] {
        let selectPattern = "<select[^>]*name=[\"']questionid[\"'][^>]*>(.*?)</select>"
        guard let selectRegex = try? NSRegularExpression(
                pattern: selectPattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let selectMatch = selectRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let selectRange = Range(selectMatch.range(at: 1), in: html) else {
            return SecurityQuestion.defaultList
        }

        let inner = String(html[selectRange])
        let optionPattern = "<option[^>]*value=[\"'](\\d+)[\"'][^>]*>(.*?)</option>"
        guard let optionRegex = try? NSRegularExpression(
                pattern: optionPattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return SecurityQuestion.defaultList
        }

        var result: [SecurityQuestion] = []
        optionRegex.enumerateMatches(in: inner, range: NSRange(inner.startIndex..., in: inner)) { match, _, _ in
            guard let match,
                  let idRange = Range(match.range(at: 1), in: inner),
                  let textRange = Range(match.range(at: 2), in: inner) else { return }
            let id = Int(String(inner[idRange])) ?? 0
            let raw = String(inner[textRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(SecurityQuestion(id: id, text: raw.isEmpty ? "（无）" : raw))
        }

        return result.isEmpty ? SecurityQuestion.defaultList : result
    }
}
