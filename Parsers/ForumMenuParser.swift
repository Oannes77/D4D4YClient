import Foundation
import SwiftSoup

/// 解析站点自带的版块导航菜单（每个 Discuz! 页面都包含）。
///
/// 说明：index.php 是唯一能直接看全站版块的入口，但它被 Cloudflare 质询稳定拦截（403）。
/// 因此版块列表改从普通页面里的导航容器解析。
///
/// **两套模板的容器名不同**，这里逐个尝试，全落空时退回「整页扫描所有 forumdisplay 链接」：
/// - WAP：`<div id="silder_l" class="silder_l am-offcanvas">` 侧边抽屉
/// ```
/// <dl><dt><a href="index.php?gid=35">4D4Y</a></dt>
///     <dd><ul>
///       <li><a href="forumdisplay.php?fid=7">Geek Talks · 奇客怪谈</a></li>
///       <li class="sub"><a href="forumdisplay.php?fid=62">Joggler</a></li>
///     </ul></dd></dl>
/// ```
/// - PC ：`div#nv` / `div#nv_forum` 顶部导航条
enum ForumMenuParser {

    /// 导航容器候选（按可信度排序）。
    private static let scopeSelectors = ["#silder_l", "div#nv_forum", "div#nv", "div#menu", "div.nav"]

    static func parse(html: String) throws -> [ForumSection] {
        let document = try SwiftSoup.parse(html)

        var scopes: [Element] = []
        for selector in scopeSelectors {
            if let el = (try? document.select(selector).first()) ?? nil { scopes.append(el) }
        }
        // 全部落空：整页扫描（去重后仍可用，只是可能混入面包屑里的同 fid 链接 —— 已被 seen 挡掉）
        if scopes.isEmpty {
            Log.parser.warning("未匹配到导航容器，退回整页扫描 forumdisplay 链接")
            scopes = [document]
        }

        var seen = Set<Int>()
        var sections: [ForumSection] = []
        for scope in scopes {
            let links = (try? scope.select("a[href*='forumdisplay.php?fid=']")) ?? Elements()
            for link in links.array() {
                guard let href = try? link.attr("href"),
                      let range = href.range(of: #"fid=(\d+)"#, options: .regularExpression),
                      let fid = Int(href[range].dropFirst(4)),
                      let name = try? link.text(),
                      !name.isEmpty else { continue }
                guard seen.insert(fid).inserted else { continue }

                // 子版块：WAP 用 <li class="sub">；PC 常在 <ul class="child"> 内 —— 父链上任一环节带 sub/child 即判定
                let isSub = Self.looksLikeSubForum(link)
                sections.append(ForumSection(id: fid, name: name, isSubForum: isSub))
            }
        }
        Log.parser.info("ForumMenuParser: 解析到 \(sections.count) 个版块")
        return sections
    }

    /// 沿父链向上若干层看类名是否含 sub / child。
    /// 注：SwiftSoup 的 `parent()` / `tagName()` 均不抛错（只有 `select` / `attr` / `text` 等抛），故不加 `try?`。
    private static func looksLikeSubForum(_ link: Element) -> Bool {
        var node: Element? = link.parent()
        var depth = 0
        while let current = node, depth < 3 {
            let cls = ((try? current.attr("class")) ?? "").lowercased()
            let tag = current.tagName().lowercased()
            if cls.contains("sub") || cls.contains("child") || tag == "dd" { return true }
            node = current.parent()
            depth += 1
        }
        return false
    }
}
