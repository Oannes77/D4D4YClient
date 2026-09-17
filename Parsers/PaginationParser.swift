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

/// 分页解析。
/// 真实结构（经 fid=14 第 1/2 页与 tid=193033 第 1/2 页验证）：
///   当前页/总页数：<strong class="fade">1/919</strong>
///   翻页按钮：    <input onclick="location.href = 'forumdisplay.php?fid=14&page=2'"
///                         value="下一页 >" />
/// 上一页/下一页通过 onclick 中的相对 URL 与 page 参数匹配，不写死任何 URL。
enum PaginationParser {

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

    /// - Parameter document: 已解码的整个页面
    static func parse(document: Document) -> PageInfo? {
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
}
