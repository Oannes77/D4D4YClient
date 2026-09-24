import Foundation
import SwiftSoup

/// 解析板块页顶部的工具栏（**PC 模板**；WAP 模板没有这套工具栏）。
///
/// 真实页面结构（`forumdisplay.php?fid=14`，游客可见，`Tests/Fixtures/forumdisplay_fid14_page1_pc.html` 实测）：
///
/// ```html
/// <!-- ① 主题分类：独立容器，每个板块各不相同 -->
/// <div class="threadtype">
///   <p>
///     <a href="forumdisplay.php?fid=14&filter=type&typeid=10&sid=xxx">心得技巧</a>
///     <a href="…typeid=18…">求助</a> …
///   </p>
/// </div>
///
/// <!-- ② 工具栏：全部 / 精华 / 时间 / 热门 -->
/// <ul class="itemfilter s_clear">
///   <li>主题:</li>
///   <li class="current"><a href="forumdisplay.php?fid=14&sid=xxx"><span>全部</span></a></li>
///   <li><a class="filter" href="…filter=digest…">精华</a></li>   ← 跳过
///   <li class="pipe">|</li>
///   <li>时间:</li>
///   <li><a href="…orderby=lastpost&filter=86400…"><span>一天</span></a></li>
///   … 两天 / 周 / 月 / 季
///   <li><a class="order" href="…filter=&orderby=heats…">热门</a></li>
/// </ul>
/// ```
///
/// 原则：**只搬运页面里已有的链接**，不拼参数、不硬编码 typeid 表（每个板块都不一样）。
enum BoardFilterParser {

    /// 不做的筛选项（用户判定用处不大）。命中这些的链接一律跳过。
    private static let skippedFilters = ["digest", "poll", "activity"]

    // MARK: - 板块排序条（首页用）

    /// 排序 / 时间条。**不含主题分类** —— 分类是发帖时的选项，见 `categories(document:)`。
    static func parse(document: Document) -> BoardFilterBar? {
        let sorts = parseSorts(document: document)
        let bar = BoardFilterBar(sorts: sorts)
        if bar.isEmpty {
            Log.parser.info("BoardFilterParser 未解析到排序条（WAP 模板或版块无排序入口）")
            return nil
        }
        Log.parser.info("BoardFilterParser 排序时间 \(sorts.count) 项")
        return bar
    }

    private static func parseSorts(document: Document) -> [BoardFilterOption] {
        guard let toolbar = (try? document.select("ul.itemfilter").first()) ?? nil else { return [] }
        var options: [BoardFilterOption] = []
        for anchor in (try? toolbar.select("a")) ?? Elements() {
            let href = clean((try? anchor.attr("href")) ?? "")
            guard !href.isEmpty else { continue }
            // 排序 / 时间：href 里带 orderby=，或 filter=<纯数字秒>
            let isSort = href.contains("orderby=") || (try? href.range(of: #"filter=\d+"#,
                                                                     options: .regularExpression)) != nil
            guard isSort else { continue }
            guard !skippedFilters.contains(where: { href.contains("filter=" + $0) }) else { continue }
            let title = ((try? anchor.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            guard !options.contains(where: { $0.path == href }) else { continue }
            options.append(BoardFilterOption(title: title, path: href, isSelected: isCurrent(anchor)))
        }
        return options
    }

    // MARK: - 主题分类（发帖页用）

    /// 某板块的**主题分类**：从板块页 `div.threadtype` 里的分类链接解析出 `typeid` 与名字。
    ///
    /// `forumdisplay.php?fid=14&filter=type&typeid=10` → `BoardCategory(id: 10, name: "心得技巧")`。
    /// 该板块没有开分类时返回空数组（发帖页据此不显示分类选择，不摆一个空下拉）。
    static func categories(document: Document) -> [BoardCategory] {
        var result: [BoardCategory] = []
        for anchor in (try? document.select("div.threadtype a[href*=filter=type]")) ?? Elements() {
            let href = clean((try? anchor.attr("href")) ?? "")
            guard let range = href.range(of: #"typeid=(\d+)"#, options: .regularExpression),
                  let typeID = Int(href[range].dropFirst("typeid=".count)) else { continue }
            let name = ((try? anchor.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            guard !result.contains(where: { $0.id == typeID }) else { continue }
            result.append(BoardCategory(id: typeID, name: name))
        }
        return result
    }

    static func categories(html: String) throws -> [BoardCategory] {
        categories(document: try SwiftSoup.parse(html))
    }

    // MARK: - 工具

    /// 剥掉 `sid` 与实体转义（我们始终带 Cookie，不需要会话 ID 随链接传递）。
    private static func clean(_ href: String) -> String {
        PaginationParser.strippingSessionID(
            href.replacingOccurrences(of: "&amp;", with: "&")
        )
    }

    /// 选中态：页面把当前项标在 `<li class="current">` 或链接自身的 class 上；
    /// 有些版块用 `<strong>` 包住当前项。认不出来就当未选中（宁可不高亮，也不假装选中）。
    private static func isCurrent(_ anchor: Element) -> Bool {
        if let cls = try? anchor.className(), cls.contains("current") { return true }
        if let parent = anchor.parent(), let cls = try? parent.className(), cls.contains("current") {
            return true
        }
        if let grandparents = anchor.parent()?.parent(),
           let cls = try? grandparents.className(), cls.contains("current") {
            return true
        }
        // `parent()` / `tagName()` 都不抛错，不要套多余的 `try?`。
        return (anchor.parent()?.tagName() ?? "") == "strong"
    }
}
