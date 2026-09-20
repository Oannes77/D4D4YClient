import Foundation
import SwiftSoup

/// 解析 Discuz! `pm.php` 短消息列表页（站内短信 / 系统消息）。
///
/// ⚠️ 结构未在本地验证：`pm.php` 必须登录才可达，游客访问同类权限页（实测 `space.php`）
/// 返回「…无法进行此操作」+ 登录表单。因此这里采用**登录门判定 + 通用锚点抽取**的
/// 防御式实现，任何模板下都给出「可用结果」或「明确失败」，**绝不伪造消息**：
///
/// 1. 命中登录门 → `.requiresLogin`
/// 2. 抽取所有指向 `pm.php` 且带 pmid / uid 的链接，每条 = 一条短信：
///    标题取链接文本，时间取所在容器内首个日期，发件人取容器内最近的 `space.php?uid=` 链接
///    纯导航链接（「短消息」「发送短消息」）没有 pmid/uid/时间，自动跳过
/// 3. 一条都没抽到且页面上完全没有 pm 链接 → `.empty`（空收件箱）
/// 4. 抽到候选但全部无效 → `.unsupported`（结构未识别，界面明确告知，不编造内容）
struct PMListParser {

    enum Outcome {
        case messages([PrivateMessage])
        case empty
        case requiresLogin
        case unsupported
    }

    /// 判定「登录门 / 权限不足」页面。
    /// 实测文案：游客访问 `space.php` → 「…无法进行此操作。」+ 登录表单；
    /// `pm.php` / `search.php` 同类页面文案一致（search 为「您还未登录，无法进行此操作」）。
    static func isLoginGate(_ html: String) -> Bool {
        html.contains("您还未登录")
            || html.contains("无法进行此操作")
            || html.contains("无权进行当前操作")
    }

    /// - Parameter systemSegment: 系统消息页允许条目没有时间（部分通知不带时间）。
    static func parse(html: String, systemSegment: Bool = false) -> Outcome {
        if isLoginGate(html) { return .requiresLogin }
        guard let doc = try? SwiftSoup.parse(html) else { return .unsupported }

        let anchors = ((try? doc.select("a[href*='pm.php']"))?.array()) ?? []
        if anchors.isEmpty { return .empty }

        var seen = Set<String>()
        var items: [PrivateMessage] = []

        for anchor in anchors {
            let rawHref = (try? anchor.attr("href")) ?? ""
            guard let key = identityKey(href: rawHref), !seen.contains(key) else { continue }

            let container = containerElement(around: anchor)
            let containerText = container.flatMap { try? $0.text() } ?? ""
            let containerHTML = container.flatMap { try? $0.html() } ?? ""

            // 标题 = 链接文本；为空时退回正文首行
            var title = ((try? anchor.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let timeRaw = firstDate(in: containerText) ?? ""
            if title.isEmpty { title = firstLine(of: containerText) }
            guard !title.isEmpty else { continue }
            // 没有任何时间信息的链接视为站内导航，不是一条短信
            guard !timeRaw.isEmpty || systemSegment else { continue }

            // 发件人：容器内最近的 space.php?uid= 链接
            var userName = ""
            var uid: Int?
            if let container,
               let userLink = try? container.select("a[href*='space.php?uid=']").first() {
                userName = ((try? userLink.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                uid = uidFromHref((try? userLink.attr("href")) ?? "")
            }

            var preview = containerText
            for token in [title, timeRaw, userName] where !token.isEmpty {
                preview = preview.replacingOccurrences(of: token, with: " ")
            }
            preview = collapseWhitespace(preview)
            if preview.count > 80 { preview = String(preview.prefix(80)) }

            var isUnread: Bool?
            let classAttr = (container.flatMap { try? $0.attr("class") } ?? "").lowercased()
            if containerHTML.contains("未读")
                || classAttr.contains("unread")
                || classAttr.contains("new") {
                isUnread = true
            } else {
                let tag = anchor.tagName().lowercased()
                if tag == "strong" || tag == "b" { isUnread = true }
            }

            seen.insert(key)
            items.append(PrivateMessage(
                id: key,
                pmid: intValue(in: rawHref, pattern: #"pmid=(\d+)"#),
                userID: uid,
                userName: userName.isEmpty ? (systemSegment ? "系统消息" : "未知用户") : userName,
                subject: title,
                preview: preview,
                timeRaw: timeRaw,
                isUnread: isUnread
            ))
        }

        if items.isEmpty {
            Log.parser.error("PMListParser 抽到 \(anchors.count, privacy: .public) 个 pm 链接但无有效短信（结构未识别）")
            return .unsupported
        }
        Log.parser.info("PMListParser: \(items.count, privacy: .public) 条短信")
        return .messages(items)
    }

    // MARK: - 结构定位

    /// 从链接向上最多 4 层寻找「含日期」的容器，作为这条短信所在的块。
    private static func containerElement(around anchor: Element) -> Element? {
        var node: Element? = anchor.parent()
        var depth = 0
        while let current = node, depth < 4 {
            if let text = try? current.text(), firstDate(in: text) != nil { return current }
            node = current.parent()
            depth += 1
        }
        return anchor.parent()
    }

    /// 去掉 `sid=` 会话参数后的稳定标识；无 pmid / uid 的导航链接返回 nil。
    private static func identityKey(href: String) -> String? {
        let clean = href
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"[&?]sid=[^&]*"#, with: "", options: .regularExpression)
        guard clean.contains("pm.php") else { return nil }
        if let pmid = intValue(in: clean, pattern: #"pmid=(\d+)"#) { return "pmid:\(pmid)" }
        if let uid = intValue(in: clean, pattern: #"uid=(\d+)"#) { return "pm:uid:\(uid)" }
        return nil
    }

    // MARK: - 文本工具

    /// 日期 / 时间的宽松识别：`2004-11-3 22:22` / `11-3 22:22` / `昨天 21:04` / `09:02`。
    static let datePattern = #"\d{4}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2})?"#
        + #"|\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}"#
        + #"|[昨今前]天(?:\s*\d{1,2}:\d{2})?"#
        + #"|\d{1,2}:\d{2}"#

    /// 取文本中第一处日期 / 时间原文。
    static func firstDate(in text: String) -> String? {
        guard let range = text.range(of: datePattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    static func uidFromHref(_ href: String) -> Int? {
        intValue(in: href, pattern: #"uid=(\d+)"#)
    }

    /// 取第一行非空文本（短信没有标题时用它当标题）。
    static func firstLine(of text: String) -> String {
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t.count > 40 ? String(t.prefix(40)) : t }
        }
        return ""
    }

    static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 正则第 1 个捕获组的整数值。
    static func intValue(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text,
                                           range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }
}
