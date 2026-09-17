import Foundation
import SwiftSoup

/// 解析 forumdisplay.php 主题列表。
///
/// 真实 DOM（Discuz! 7.2 + 定制 wap 模板，已用 fid=14 第 1/2 页验证）：
/// ```
/// <tr>
///   <td class="list_user"><a href="space.php?uid=182853" class="user"><img .../></a></td>
///   <td class="listcon">
///     <p><a href="space.php?uid=182853">rrambo</a> / 2005-8-27</p>
///     <em>[<a href="forumdisplay.php?fid=14&filter=type&typeid=10">心得技巧</a>]</em>
///     <a href="viewthread.php?tid=269563&extra=page%3D1" class="title">标题</a>
///     <p><a href="space.php?username=ximeng1018">ximeng1018</a>
///        / <a href="redirect.php?tid=...&goto=lastpost#lastpost">2012-12-27 21:38</a></p>
///   </td>
///   <td width="70" align="right"><a href="#" class="num">296</a></td>
/// </tr>
/// ```
/// 注意：
/// - 该模板只有一个数字列（回复数），**没有查看数**。
/// - 匿名帖作者 <p> 内无 <a> 链接。
/// - 置顶/普通帖行结构完全相同，无法从行内稳定区分。
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

        // 版块名来自面包屑导航最后一节
        let forumName = extractForumName(from: document)

        let rows = try document.select("tr:has(td.listcon)")
        guard !rows.isEmpty() else {
            Log.parser.fault("Selector 未匹配任何主题行 (tr:has(td.listcon))")
            throw ListParseError.emptyThreadList
        }

        var threads: [ForumThread] = []
        var diagnostics = Diagnostics()
        diagnostics.rowCount = rows.size()

        for row in rows {
            // 单行解析完全容错：任何字段缺失只记诊断，不中断整页。
            if let thread = parseRow(row, diagnostics: &diagnostics) {
                threads.append(thread)
                diagnostics.parsedRowCount += 1
            }
        }
        Log.parser.info("ThreadListParser \(diagnostics.summary, privacy: .public)")

        let pageInfo = PaginationParser.parse(document: document)
            ?? PageInfo(currentPage: 1, totalPages: 1, previousPageURL: nil, nextPageURL: nil)
        return ThreadListPage(forumName: forumName, threads: threads, pageInfo: pageInfo)
    }

    private static func extractForumName(from document: Document) -> String? {
        // <div class="w navbar">... » <a href="forumdisplay.php?fid=14">版块名</a> » 标题
        guard let navbar = try? document.select("div.navbar").first(),
              let links = try? navbar.select("a[href*='forumdisplay.php']") else { return nil }
        guard links.size() > 0 else { return nil }
        return try? links.get(links.size() - 1).text()
    }

    // MARK: - 单行解析

    private static func parseRow(_ row: Element, diagnostics: inout Diagnostics) -> ForumThread? {
        guard let titleLink = try? row.select("a.title").first(),
              let title = try? titleLink.text(),
              !title.isEmpty,
              let href = try? titleLink.attr("href"),
              let tid = extractTID(from: href) else {
            Log.parser.warning("主题行缺少 a.title 或 tid，跳过该行")
            return nil
        }

        // 分类前缀 [心得技巧]
        let typeName = (try? row.select("em a").first()?.text()) ?? nil
        // td.listcon 内两个 <p>：作者+发帖日期、最后回复者+最后回复时间
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
            views: nil,                      // wap 模板不输出查看数
            lastReplyUserName: lastReplyUserName,
            lastReplyAtRaw: lastReplyAtRaw
        )
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
