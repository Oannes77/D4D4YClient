import Foundation
import SwiftSoup

/// 解析 forumdisplay.php 主题列表（**两套模板都认**）。
///
/// **PC 模板**（全局默认；已用 `fid=14` 真实页面验证，75 行全部命中）：
/// ```
/// <tbody id="normalthread_269563">
///   <tr>
///     <td class="folder">…</td><td class="icon">…</td>
///     <th class="subject common">
///       <em>[<a href="forumdisplay.php?fid=14&filter=type&typeid=10">心得技巧</a>]</em>
///       <span id="thread_269563"><a href="viewthread.php?tid=269563&…">标题</a></span>
///       <img src="…/images/attachicons/common.gif" alt="附件" class="attach" />
///     </th>
///     <td class="author"><cite><a href="space.php?uid=182853">rrambo</a></cite><em>2005-8-27</em></td>
///     <td class="nums"><strong>1022</strong>/<em>607982</em></td>   ← 回复数 / 查看数
///     <td class="lastpost"><cite><a href="space.php?username=tzdrl">tzdrl</a></cite>
///         <em><a href="redirect.php?tid=…&goto=lastpost#lastpost">2026-9-17 16:22</a></em></td>
///   </tr>
/// </tbody>
/// ```
/// **WAP 模板**（兜底）：`tr:has(td.listcon)` + `a.title`，见 `parseWAPRow`。
///
/// 两套的差异：**PC 模板有查看数**（`td.nums > em`），WAP 模板完全不输出，故 WAP 下 `views` 恒为 nil。
struct ThreadListParser {

    /// 行级解析诊断信息，供 Debug 区分“Selector 未匹配 / 字段缺失”。
    struct Diagnostics {
        var rowCount = 0
        var parsedRowCount = 0
        var missingAuthor = 0
        var missingAuthorUID = 0
        var missingReplies = 0
        var missingDate = 0

        var summary: String {
            "rows=\(rowCount) ok=\(parsedRowCount) noAuthor=\(missingAuthor) " +
            "noUID=\(missingAuthorUID) noReplies=\(missingReplies) noDate=\(missingDate)"
        }
    }

    enum ListParseError: Error {
        /// 主题列表为空（可能是版块不存在、被限制访问或模板改版）
        case emptyThreadList
    }

    static func parse(html: String) throws -> ThreadListPage {
        let document = try SwiftSoup.parse(html)
        let forumName = extractForumName(from: document)

        if let page = parsePC(document: document, forumName: forumName) {
            return page
        }
        Log.parser.warning("PC 模板未命中主题行，回退 WAP 模板解析")
        return try parseWAP(document: document, forumName: forumName)
    }

    // MARK: - PC 模板

    private static func parsePC(document: Document, forumName: String?) -> ThreadListPage? {
        guard let rows = try? document.select("tbody[id^=normalthread_]"), rows.size() > 0 else {
            return nil
        }

        var threads: [ForumThread] = []
        var diagnostics = Diagnostics()
        diagnostics.rowCount = rows.size()
        for row in rows {
            if let thread = parsePCRow(row, diagnostics: &diagnostics) {
                threads.append(thread)
                diagnostics.parsedRowCount += 1
            }
        }
        guard !threads.isEmpty else { return nil }
        Log.parser.info("ThreadListParser(PC) \(diagnostics.summary, privacy: .public)")

        let pageInfo = PaginationParser.parse(document: document)
            ?? PageInfo(currentPage: 1, totalPages: 1, previousPageURL: nil, nextPageURL: nil)
        return ThreadListPage(forumName: forumName, threads: threads, pageInfo: pageInfo)
    }

    private static func parsePCRow(_ row: Element, diagnostics: inout Diagnostics) -> ForumThread? {
        // 标题链接：PC 模板把标题包在 span#thread_<tid> 里；`a.xst` 是 Discuz 原生类名，作为兜底。
        var titleLink: Element? = (try? row.select("th.subject span[id^=thread_] > a").first()) ?? nil
        if titleLink == nil { titleLink = (try? row.select("a.xst").first()) ?? nil }

        let rowID = (try? row.attr("id")) ?? ""
        guard let titleLink,
              let title = try? titleLink.text(), !title.isEmpty,
              let href = try? titleLink.attr("href"),
              let tid = extractTID(fromRowID: rowID) ?? extractTID(from: href) else {
            Log.parser.warning("PC 列表行缺少标题或 tid，跳过该行")
            return nil
        }

        // 分类前缀 [心得技巧]
        let typeName = (try? row.select("th.subject em a").first()?.text()) ?? nil

        var authorName = "匿名"
        var authorID: Int?
        if let authorLink = (try? row.select("td.author cite > a").first()) ?? nil {
            authorName = (try? authorLink.text()) ?? authorName
            authorID = extractUID(from: (try? authorLink.attr("href")) ?? "")
            if authorID == nil { diagnostics.missingAuthorUID += 1 }
        } else {
            diagnostics.missingAuthor += 1
        }

        let createdAtRaw = (((try? row.select("td.author em").first()?.text()) ?? nil) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if createdAtRaw.isEmpty { diagnostics.missingDate += 1 }

        // 回复 / 查看：PC 模板 <td class="nums"><strong>回复</strong>/<em>查看</em></td>
        var replies: Int?
        var views: Int?
        if let s = ((try? row.select("td.nums strong").first()?.text()) ?? nil),
           let n = Int(s.trimmingCharacters(in: .whitespaces)) { replies = n }
        if let s = ((try? row.select("td.nums em").first()?.text()) ?? nil),
           let n = Int(s.trimmingCharacters(in: .whitespaces)) { views = n }
        if replies == nil {
            // 兜底：整格文本形如 "1022/607982"
            let cell = (((try? row.select("td.nums").first()?.text()) ?? "") )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = cell.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 1 { replies = Int(parts[0]) }
            if parts.count >= 2, views == nil { views = Int(parts[1]) }
        }
        if replies == nil { diagnostics.missingReplies += 1 }

        let lastReplyUserName = (try? row.select("td.lastpost cite > a").first()?.text()) ?? nil
        let lastReplyAtRaw = (try? row.select("td.lastpost em > a").first()?.text()) ?? nil

        return ForumThread(
            id: tid,
            title: title,
            typeName: typeName,
            authorName: authorName,
            authorID: authorID,
            createdAt: DiscuzDateParser.parse(createdAtRaw),
            createdAtRaw: createdAtRaw,
            replies: replies,
            views: views,
            lastReplyUserName: lastReplyUserName,
            lastReplyAtRaw: lastReplyAtRaw
        )
    }

    // MARK: - WAP 模板（兜底）

    private static func parseWAP(document: Document, forumName: String?) throws -> ThreadListPage {
        let rows = try document.select("tr:has(td.listcon)")
        guard !rows.isEmpty() else {
            Log.parser.fault("Selector 未匹配任何主题行（PC 与 WAP 都不命中）")
            throw ListParseError.emptyThreadList
        }

        var threads: [ForumThread] = []
        var diagnostics = Diagnostics()
        diagnostics.rowCount = rows.size()
        for row in rows {
            if let thread = parseWAPRow(row, diagnostics: &diagnostics) {
                threads.append(thread)
                diagnostics.parsedRowCount += 1
            }
        }
        Log.parser.info("ThreadListParser(WAP) \(diagnostics.summary, privacy: .public)")

        let pageInfo = PaginationParser.parse(document: document)
            ?? PageInfo(currentPage: 1, totalPages: 1, previousPageURL: nil, nextPageURL: nil)
        return ThreadListPage(forumName: forumName, threads: threads, pageInfo: pageInfo)
    }

    private static func parseWAPRow(_ row: Element, diagnostics: inout Diagnostics) -> ForumThread? {
        guard let titleLink = try? row.select("a.title").first(),
              let title = try? titleLink.text(),
              !title.isEmpty,
              let href = try? titleLink.attr("href"),
              let tid = extractTID(from: href) else {
            Log.parser.warning("主题行缺少 a.title 或 tid，跳过该行")
            return nil
        }

        let typeName = (try? row.select("em a").first()?.text()) ?? nil
        let paragraphs = (try? row.select("td.listcon > p")) ?? Elements()

        var authorName = "匿名"
        var authorID: Int?
        var createdAtRaw = ""
        if paragraphs.size() > 0 {
            let first = paragraphs.get(0)
            if let authorLink = try? first.select("a[href*=space.php?uid=]").first() {
                authorName = (try? authorLink.text()) ?? authorName
                authorID = extractUID(from: (try? authorLink.attr("href")) ?? "")
            } else {
                diagnostics.missingAuthorUID += 1
                let text = (try? first.text()) ?? ""
                if !text.isEmpty { authorName = text.split(separator: "/").first.map(String.init) ?? "匿名" }
            }
            createdAtRaw = extractDate(afterSlash: (try? first.text()) ?? "") ?? ""
            if createdAtRaw.isEmpty { diagnostics.missingDate += 1 }
        } else {
            diagnostics.missingAuthor += 1
        }

        var lastReplyUserName: String?
        var lastReplyAtRaw: String?
        if paragraphs.size() > 1 {
            let second = paragraphs.get(1)
            lastReplyUserName = (try? second.select("a").first()?.text()) ?? nil
            if let lastLink = try? second.select("a[href*=goto=lastpost]").first() {
                lastReplyAtRaw = try? lastLink.text()
            }
        }

        var replies: Int?
        if let numEl = try? row.select("a.num").first(),
           let numText = try? numEl.text(),
           let n = Int(numText.trimmingCharacters(in: .whitespaces)) {
            replies = n
        } else {
            diagnostics.missingReplies += 1
        }

        return ForumThread(
            id: tid,
            title: title,
            typeName: typeName,
            authorName: authorName,
            authorID: authorID,
            createdAt: DiscuzDateParser.parse(createdAtRaw),
            createdAtRaw: createdAtRaw,
            replies: replies,
            views: nil,                      // WAP 模板不输出查看数
            lastReplyUserName: lastReplyUserName,
            lastReplyAtRaw: lastReplyAtRaw
        )
    }

    // MARK: - 工具

    /// 面包屑里的版块名。PC 模板用 `div#nav`/`h1`，WAP 用 `div.navbar`，这里逐个试。
    private static func extractForumName(from document: Document) -> String? {
        let candidates = ["div.navbar", "div#nav", "div.nav", "h1"]
        for selector in candidates {
            guard let container = try? document.select(selector).first(),
                  let links = try? container.select("a[href*=forumdisplay.php]"),
                  links.size() > 0 else { continue }
            // 面包屑最后一节通常就是当前版块；排除“返回列表”之类。
            for i in stride(from: links.size() - 1, through: 0, by: -1) {
                let text = ((try? links.get(i).text()) ?? "").trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    /// `normalthread_269563` -> 269563
    private static func extractTID(fromRowID id: String) -> Int? {
        guard let range = id.range(of: #"normalthread_(\d+)"#, options: .regularExpression) else { return nil }
        return Int(id[range].split(separator: "_").last.map(String.init) ?? "")
    }

    private static func extractTID(from href: String) -> Int? {
        guard let range = href.range(of: #"tid=(\d+)"#, options: .regularExpression) else { return nil }
        return Int(href[range].dropFirst(4))
    }

    private static func extractUID(from href: String) -> Int? {
        guard let range = href.range(of: #"uid=(\d+)"#, options: .regularExpression) else { return nil }
        return Int(href[range].dropFirst(4))
    }

    /// "rrambo / 2005-8-27" -> "2005-8-27"
    private static func extractDate(afterSlash text: String) -> String? {
        guard let idx = text.firstIndex(of: "/") else { return nil }
        let rest = text[text.index(after: idx)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }
}
