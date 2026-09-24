import Foundation
import SwiftSoup

/// 解析 `search.php` 搜索结果页。
///
/// 该站为 Discuz! 7.2 + 定制 wap 模板，搜索结果页结构未在本地验证（需登录态才能拿到），
/// 因此采用**两级策略**，任一命中即可，避免模板改版导致整个搜索不可用：
///
/// 1. 优先复用列表页结构：`tr:has(td.listcon)`（与 forumdisplay 一致的 `a.title` 行）
///    —— 搜索结果模板与板块列表模板同源，命中概率高。
/// 2. 兜底通用抽取：页面内所有 `a[href*=viewthread.php?tid=]` 链接，
///    标题取链接文本，作者从其就近父节点内的 `space.php?uid=` 链接取。
///
/// 解析不到任何主题时返回空数组（调用方据此提示「没有找到相关主题」），不伪造结果。
struct SearchResultParser {

    /// 页面语义判定：用于把「无权限 / 无结果」与「解析失败」区分开。
    enum Outcome {
        case results([ForumThread])
        case noResults
        case requiresLogin
    }

    static func parse(html: String) -> Outcome {
        // 1) 权限：游客无权搜索（已实测返回「您还未登录，无法进行此操作」）
        if html.contains("您还未登录") || html.contains("无权进行当前操作") {
            return .requiresLogin
        }

        // 2) 优先复用板块列表结构（a.title + td.listcon）
        if let page = try? ThreadListParser.parse(html: html), !page.threads.isEmpty {
            return .results(page.threads)
        }

        // 3) 兜底：通用抽取 viewthread 链接
        let fallback = fallbackThreads(from: html)
        if !fallback.isEmpty { return .results(fallback) }

        // 4) 明确的「没有找到」提示
        if html.contains("没有找到") || html.contains("没有匹配") || html.contains("无搜索结果") {
            return .noResults
        }
        return .noResults
    }

    // MARK: - 兜底通用抽取

    private static func fallbackThreads(from html: String) -> [ForumThread] {
        guard let doc = try? SwiftSoup.parse(html) else { return [] }
        guard let links = try? doc.select("a[href*=viewthread.php]") else { return [] }

        var seen = Set<Int>()
        var threads: [ForumThread] = []

        for link in links.array() {
            guard let href = try? link.attr("href"),
                  let tid = tid(from: href),
                  !seen.contains(tid) else { continue }
            let title = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count >= 2 else { continue }

            var authorName = "匿名"
            var authorID: Int?
            if let parent = link.parent(),
               let userLink = try? parent.select("a[href*=space.php?uid=]").first(),
               let name = try? userLink.text(), !name.isEmpty {
                authorName = name
                let userHref = (try? userLink.attr("href")) ?? ""
                authorID = uid(from: userHref)
            }

            seen.insert(tid)
            threads.append(ForumThread(
                id: tid,
                title: title,
                typeName: nil,
                authorName: authorName,
                authorID: authorID,
                createdAt: nil,
                createdAtRaw: "",
                replies: nil,
                views: nil,
                lastReplyUserName: nil,
                lastReplyAtRaw: nil
            ))
        }
        Log.parser.info("SearchResultParser 兜底抽取 \(threads.count, privacy: .public) 条")
        return threads
    }

    private static func tid(from href: String) -> Int? {
        guard let range = href.range(of: #"tid=(\d+)"#, options: .regularExpression) else { return nil }
        return Int(href[range].dropFirst(4))
    }

    private static func uid(from href: String) -> Int? {
        guard let range = href.range(of: #"uid=(\d+)"#, options: .regularExpression) else { return nil }
        return Int(href[range].dropFirst(4))
    }
}
