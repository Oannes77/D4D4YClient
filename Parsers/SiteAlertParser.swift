import Foundation
import SwiftSoup

/// 识别站点的「提示信息」页（登录门 / 权限不足）—— **排在模板解析之前**。
///
/// 选择器只用结构、不匹配文案，站点改字也不会失效；实测（2026-09-24）：
///
/// | 页面 | `div.fcontent.alert_win` | `alert_error p` | `form#loginform` |
/// |---|---|---|---|
/// | 登录门 `forumdisplay.php?fid=2`（7168 B） | 1 | 2 段 | 1 |
/// | 正常版块 `forumdisplay.php?fid=14`（92320 B） | 0 | 0 | 0 |
/// | 正常详情 `viewthread.php?tid=193033` | 0 | 0 | 0 |
///
/// ⚠️ 同一张模板 Discuz 也用来报「回复成功」「发帖成功」这类结果页，
/// 所以本解析器**只负责如实描述页面**，由调用方决定含义
/// （`hasLoginForm == true` ⇒ 登录是出路；否则只是「站点拒绝了这次请求」）。
struct SiteAlertParser {

    /// 命中提示页返回详情；正常内容页返回 nil。
    static func parse(document: Document) -> SiteAlert? {
        guard let window = (try? document.select("div.fcontent.alert_win").first()) ?? nil else {
            return nil
        }

        let paragraphs = errorParagraphs(in: window)
        let fallback = ((try? window.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let message = paragraphs.isEmpty ? fallback : paragraphs.joined(separator: " ")
        // 空壳（结构在、文案空）不算提示页，交回给模板解析器按老路报错，避免「静默吞掉」。
        guard !message.isEmpty else { return nil }

        let alert = SiteAlert(message: message,
                              reason: paragraphs.last,
                              hasLoginForm: hasLoginForm(in: document))
        Log.parser.info("命中站点提示页(loginForm=\(alert.hasLoginForm, privacy: .public)): \(message, privacy: .public)")
        return alert
    }

    static func parse(html: String) -> SiteAlert? {
        guard let document = try? SwiftSoup.parse(html) else { return nil }
        return parse(document: document)
    }

    // MARK: - 内部

    /// `div.alert_error` 下的段落文本（丢掉空段）。
    private static func errorParagraphs(in window: Element) -> [String] {
        guard let nodes = try? window.select("div.alert_error p") else { return [] }
        var out: [String] = []
        for node in nodes {
            guard let text = try? node.text() else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out.append(trimmed) }
        }
        return out
    }

    /// 页面里是否有可用的登录表单（Discuz 的门禁页带 `#loginform`，成功/失败提示页不带）。
    private static func hasLoginForm(in document: Document) -> Bool {
        if let forms = try? document.select("form#loginform"), forms.size() > 0 { return true }
        if let forms = try? document.select("form[action*=logging.php]"), forms.size() > 0 { return true }
        return false
    }
}
