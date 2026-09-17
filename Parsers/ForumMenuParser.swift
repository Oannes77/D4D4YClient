import Foundation
import SwiftSoup

/// 解析站点自带的版块导航菜单（每个 Discuz! 页面都包含）。
///
/// 说明：index.php 是唯一能直接看全站版块的入口，但它被 Cloudflare 质询稳定拦截（403）。
/// 因此版块列表改从 forumdisplay / viewthread 页面的侧边抽屉 #silder_l 解析：
/// ```
/// <div id="silder_l" class="silder_l am-offcanvas">
///   <dl><dt><a href="index.php?gid=35">4D4Y</a></dt>
///       <dd><ul>
///         <li><a href="forumdisplay.php?fid=7">Geek Talks · 奇客怪谈</a></li>
///         <li class="sub"><a href="forumdisplay.php?fid=62">Joggler</a></li>
///         ...
///       </ul></dd></dl>
/// </div>
/// ```
enum ForumMenuParser {

    static func parse(html: String) throws -> [ForumSection] {
        let document = try SwiftSoup.parse(html)
        guard let menu = try? document.select("#silder_l").first() else {
            Log.parser.warning("Selector 未匹配 #silder_l，无法获取版块菜单")
            return []
        }

        var seen = Set<Int>()
        var sections: [ForumSection] = []
        let links = (try? menu.select("li a[href*='forumdisplay.php?fid=']")) ?? Elements()
        for link in links.array() {
            guard let href = try? link.attr("href"),
                  let range = href.range(of: #"fid=(\d+)"#, options: .regularExpression),
                  let fid = Int(href[range].dropFirst(4)),
                  let name = try? link.text(),
                  !name.isEmpty else { continue }
            guard seen.insert(fid).inserted else { continue }

            // 子版块的 class="sub" 在 <li> 上
            let parentClass = (try? link.parent()?.attr("class")) ?? ""
            let isSub = parentClass.split(separator: " ").contains("sub")

            sections.append(ForumSection(id: fid, name: name, isSubForum: isSub))
        }
        Log.parser.info("ForumMenuParser: 解析到 \(sections.count) 个版块")
        return sections
    }
}
