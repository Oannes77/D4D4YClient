import Foundation
import SwiftSoup

/// 解析板块页顶部的筛选条（**PC 模板**；WAP 模板没有这套工具栏，返回 nil 即可）。
///
/// 真实页面结构（`forumdisplay.php?fid=14`，游客可见，`tests/Fixtures/forumdisplay_fid14_page1_pc.html` 实测）：
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

    static func parse(document: Document) -> BoardFilterBar? {
        let categories = parseCategories(document: document)
        let sorts = parseSorts(document: document)
        let bar = BoardFilterBar(categories: categories, sorts: sorts)
        if bar.isEmpty {
            Log.parser.info("BoardFilterParser 未解析到筛选条（WAP 模板或版块无分类）")
            return nil
        }
        Log.parser.info("BoardFilterParser 分类 \(categories.count) 项 / 排序时间 \(sorts.count) 项")
        return bar
    }

    // MARK: - 主题分类

    private static func parseCategories(document: Document) -> [BoardFilterOption] {
        var options: [BoardFilterOption] = []

        // 「全部」取自工具栏里那个**既没有 filter 也没有 orderby** 的当前项
        // （`<li class="current"><a href="forumdisplay.php?fid=14&sid=xxx">全部</a></li>`）。
        if let toolbar = (try? document.select("ul.itemfilter").first()) ?? nil {
            for anchor in (try? toolbar.select("a")) ?? Elements() {
                let href = clean((try? anchor.attr("href")) ?? "")
                guard !href.isEmpty, !href.contains("filter="), !href.contains("orderby=") else { continue }
                let title = ((try? anchor.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                options.append(BoardFilterOption(title: title,
                                                 path: href,
                                                 isSelected: isCurrent(anchor)))
                break        // 工具栏里这样的项只会有一个
            }
        }

        // 分类列表
        for anchor in (try? document.select("div.threadtype a[href*=filter=type]")) ?? Elements() {
            let href = clean((try? anchor.attr("href")) ?? "")
            guard href.contains("typeid=") else { continue }
            let title = ((try? anchor.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            guard !options.contains(where: { $0.path == href }) else { continue }
            options.append(BoardFilterOption(title: title, path: href, isSelected: isCurrent(anchor)))
        }
        return options
    }

    // MARK: - 排序与时间

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
