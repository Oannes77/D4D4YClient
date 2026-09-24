import Foundation
import SwiftSoup

/// Discuz! 7.2 时间字符串解析。
/// 该站出现过的形态：`2004-7-22`、`2004-7-22 00:42`、`发表于 2004-7-22 00:42`。
/// 解析失败时返回 nil，但原始字符串始终保留在模型的 *Raw 字段中。
enum DiscuzDateParser {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-M-d HH:mm"
        return f
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-M-d"
        return f
    }()

    static func parse(_ raw: String?) -> Date? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        if s.hasPrefix("发表于") { s = String(s.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        if let d = formatter.date(from: s) { return d }
        if let d = dateOnlyFormatter.date(from: s) { return d }
        return nil
    }
}

/// 分页解析（**两套模板都认**）。
///
/// - **PC 模板**（全局默认）：
///   ```
///   <div class="pages"><strong>1</strong><a href="…&page=2">2</a>… 
///     <a href="…&page=919" class="last">... 919</a>
///     <a href="…&page=2" class="next">下一页</a></div>
///   ```
///   当前页 = `div.pages > strong`；下一页 = `a.next`；末页 = `a.last`（文本形如 `... 919`）。
/// - **WAP 模板**（兜底）：`<strong class="fade">1/919</strong>` + `input[onclick*='page=']`。
///
/// 两套都**不硬编码 URL**：只从页面里取现成的相对地址，并剥掉 `sid`
/// （我们始终带 Cookie，不需要会话 ID 在 URL 里传递；留着会随翻页一路复制）。
enum PaginationParser {

    static func parse(document: Document) -> PageInfo? {
        parsePC(document: document) ?? parseWAP(document: document)
    }

    // MARK: - PC 模板

    private static func parsePC(document: Document) -> PageInfo? {
        guard let pages = try? document.select("div.pages").first() else { return nil }
        guard let strongText = try? pages.select("strong").first()?.text(),
              let current = Int(strongText.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        let next = ((try? pages.select("a.next").first()?.attr("href")) ?? nil)
            .map(strippingSessionID)
        let previous = ((try? pages.select("a.prev").first()?.attr("href")) ?? nil)
            .map(strippingSessionID)

        return PageInfo(currentPage: current,
                        totalPages: totalPages(in: pages, current: current),
                        previousPageURL: previous,
                        nextPageURL: next)
    }

    /// 总页数：优先 `a.last`（文本 `... 919`），兜底取所有链接里 `page` 参数的最大值。
    private static func totalPages(in pages: Element, current: Int) -> Int {
        var total = 1
        if let lastText = try? pages.select("a.last").first()?.text() {
            let digits = lastText.filter { $0.isNumber }
            if let n = Int(digits) { total = n }
        }
        var maxLinked = current
        for a in (try? pages.select("a")) ?? Elements() {
            guard let href = try? a.attr("href"),
                  let p = pageNumber(inRelativeURL: href) else { continue }
            maxLinked = max(maxLinked, p)
        }
        return max(total, maxLinked)
    }

    // MARK: - WAP 模板（兜底）

    private static func parseWAP(document: Document) -> PageInfo? {
        guard let strong = try? document.select("strong.fade").first(),
              let text = try? strong.text() else { return nil }
        let parts = text.split(separator: "/")
        guard parts.count == 2,
              let current = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let total = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
            Log.parser.warning("分页文本无法解析: \(text, privacy: .public)")
            return nil
        }

        var previous: String?
        var next: String?
        let buttons = (try? document.select("input[onclick*='page=']")) ?? Elements()
        for button in buttons {
            guard let onclick = try? button.attr("onclick"),
                  let rel = relativeURL(fromOnclick: onclick),
                  let page = pageNumber(inRelativeURL: rel) else { continue }
            if page == current - 1 { previous = rel }
            if page == current + 1 { next = rel }
        }
        return PageInfo(currentPage: current,
                        totalPages: total,
                        previousPageURL: previous,
                        nextPageURL: next)
    }

    // MARK: - 工具

    /// 从 onclick 文本里提取相对 URL，例如 forumdisplay.php?fid=14&page=2
    private static func relativeURL(fromOnclick onclick: String) -> String? {
        guard let start = onclick.firstIndex(of: "'"),
              let end = onclick.lastIndex(of: "'"), start < end else { return nil }
        return String(onclick[onclick.index(after: start)..<end])
    }

    private static func pageNumber(inRelativeURL url: String) -> Int? {
        guard let range = url.range(of: #"[?&]page=(\d+)"#, options: .regularExpression) else { return nil }
        return Int(url[range].split(separator: "=").last.map(String.init) ?? "")
    }

    /// 剥掉 `sid=<token>` 会话参数（PC 模板会给链接加上它）。
    static func strippingSessionID(_ url: String) -> String {
        var s = url.replacingOccurrences(of: #"[?&]sid=[^&]*"#, with: "",
                                         options: .regularExpression)
        // 清理剥离后可能产生的 `?&` / `&&` / 末尾 `?`
        s = s.replacingOccurrences(of: "?&", with: "?")
        s = s.replacingOccurrences(of: "&&", with: "&")
        if s.hasSuffix("?") || s.hasSuffix("&") { s.removeLast() }
        return s
    }
}
