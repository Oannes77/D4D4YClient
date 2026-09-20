import Foundation
import SwiftSoup

/// 解析与某个用户的私信往来页（`pm.php?action=view&uid=NNN`）。
///
/// ⚠️ 结构未在本地验证（需登录态）。采用**时间戳分块**启发式，对 Discuz 各类消息模板
/// 都成立：一条消息 = 一个「自身含日期」的最小块。候选块按结构猜测由细到粗依次尝试，
/// 命中即用，避免模板改版后整页不可用。
///
/// 左右分侧依据块内 `space.php?uid=` 与当前登录 uid 比对；比对不出时统一靠左，
/// 不用「猜」的方式伪造「我发出的」消息。
struct PMConversationParser {

    enum Outcome {
        case bubbles([PMBubble])
        case requiresLogin
        case unsupported
    }

    private static let candidateSelectors = [
        "li[id^=pmid]",
        "div.pmlist li",
        "ul.pmlist li",
        "div[class*=pm] li",
        "div.pmbox",
        "div.pmcon",
        "dl.pm dd",
        "ul li",
        "table tr",
        "div.w"
    ]

    static func parse(html: String, myUserID: Int?) -> Outcome {
        if PMListParser.isLoginGate(html) { return .requiresLogin }
        guard let doc = try? SwiftSoup.parse(html) else { return .unsupported }

        var blocks: [Element] = []
        for selector in candidateSelectors {
            guard let found = try? doc.select(selector), !found.isEmpty() else { continue }
            let withTime = found.array().filter { PMListParser.firstDate(in: (try? $0.text()) ?? "") != nil }
            if !withTime.isEmpty { blocks = withTime; break }
        }
        guard !blocks.isEmpty else {
            Log.parser.error("PMConversationParser 未匹配到任何含时间的消息块（结构未识别）")
            return .unsupported
        }

        var bubbles: [PMBubble] = []
        var seenTexts = Set<String>()

        for (index, block) in blocks.enumerated() {
            let text = ((try? block.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let timeRaw = PMListParser.firstDate(in: text) ?? ""

            var senderName: String?
            var senderUID: Int?
            if let link = try? block.select("a[href*='space.php?uid=']").first() {
                let name = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { senderName = name }
                senderUID = PMListParser.uidFromHref((try? link.attr("href")) ?? "")
            }

            // 正文 = 块文本去掉时间与发件人
            var body = text
            for token in [timeRaw, senderName ?? ""] where !token.isEmpty {
                body = body.replacingOccurrences(of: token, with: " ")
            }
            body = body.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
                .union(CharacterSet(charactersIn: "#/-:|·,，")))
            guard !body.isEmpty else { continue }

            let dedupeKey = "\(senderName ?? "")|\(timeRaw)|\(body)"
            guard !seenTexts.contains(dedupeKey) else { continue }
            seenTexts.insert(dedupeKey)

            let isMe = (senderUID != nil && myUserID != nil && senderUID == myUserID)
            bubbles.append(PMBubble(
                id: "pm-\(index)",
                text: body,
                timeRaw: timeRaw,
                isMe: isMe,
                senderName: senderName
            ))
        }

        guard !bubbles.isEmpty else { return .unsupported }
        Log.parser.info("PMConversationParser: \(bubbles.count, privacy: .public) 条气泡")
        return .bubbles(bubbles)
    }
}
