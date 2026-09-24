import Foundation
import SwiftSoup

/// 解析帖子正文 HTML 中的真实内容图片。
///
/// 职责边界：
/// - **只解析帖子正文（viewthread 页面）**，不解析列表页（列表页由 ThreadListParser 负责，
///   且 4D4Y 列表页本身不含图片字段，见 docs/Sprint9A-Probe.md）。
/// - 输入是 `String`（HTML），不关心编码（编码由 HTTPClient + HTMLDecoder 处理）。
/// - 必须过滤掉：头像 / 表情 / 类型图标 / 模板资源，只保留真实内容图片。
///
/// 真实数据依据（Tests/Fixtures + Sprint 9A 探查）：
/// - 头像：`https://img02.4d4y.com/forum/uc_server/data/avatar/..._avatar_small.jpg`
/// - 表情：`.../forum/images/smilies/default/biggrin.gif`
/// - 类型/状态图标：`.../forum/images/icons/iconN.gif`
/// - 模板资源：`.../forum/images/default/agree.gif`、`templates/wap/images/{fuser,logo}.png`
/// - 真实内容图：位于 `img02.4d4y.com/forum/` 之下（如 `/forum/data/attachment/...` 等）。
struct ThreadImageParser {

    /// 解析整段帖子 HTML，返回所有「真实内容图片」的绝对 URL（去重、保持出现顺序）。
    /// - Parameter html: viewthread 页面 HTML（已按 GBK/GB18030 解码）。
    /// - Returns: 内容图片 URL 数组；无图时返回空数组。
    static func parseContentImageURLs(from html: String) -> [URL] {
        // 扫描范围优先收窄到「首帖正文」：语义上首图就该来自首帖，
        // 且能天然避开 PC 模板整页的模板噪声（PC 页 <img> 数量约为 WAP 的 10 倍以上）。
        // 收窄失败时退回整页扫描（保持对旧结构的容错）。
        let scope = firstPostSection(in: html) ?? html
        let candidates = allImageSources(in: scope)
        var result: [URL] = []
        var seen = Set<String>()
        for src in candidates {
            guard let abs = resolve(src) else { continue }
            let key = abs.absoluteString.lowercased()
            guard !seen.contains(key) else { continue }
            guard isContentImage(key) else { continue }
            seen.insert(key)
            result.append(abs)
        }
        Log.parser.debug("ThreadImageParser 内容图片数量 = \(result.count, privacy: .public)")
        return result
    }

    /// 取「首帖正文」那一段 HTML，用于收窄图片扫描范围。
    ///
    /// - PC 模板：首个 `div.postmessage` —— 它同时包住正文（`td.t_msgfont`）与
    ///   **附件图列表**（`div.postattachlist > dl.t_attachlist.attachimg > img[file]`）。
    ///   ⚠️ 只取 `td.t_msgfont` 会漏掉全部附件图：实测 tid=332225，`t_msgfont` 内 4 张、
    ///   `postmessage` 内 8 张（差额正是两张附件图 + 两个附件类型图标）。
    /// - 兜底：`td.postcontent`（少数皮肤不套 `div.postmessage`）
    /// - WAP 模板：首个 `div.detailcon`
    ///
    /// 都取不到（或空）时返回 nil，调用方退回整页扫描。
    private static func firstPostSection(in html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let candidates = ["div.postmessage", "td.postcontent", "div.detailcon"]
        for selector in candidates {
            guard let el = (try? doc.select(selector).first()) ?? nil,
                  let outer = try? el.outerHtml(), !outer.isEmpty else { continue }
            return outer
        }
        return nil
    }

    // MARK: - 首帖预览文本

    /// 解析首帖纯文本摘要（首页卡片 3 行预览用）。
    ///
    /// 与图片检测共用同一次 viewthread 请求，不额外发请求。
    ///
    /// ⚠️ 必须**同时支持两套模板的容器名**（工具脚本与历史夹具仍可能是 WAP 页面）：
    /// - PC ：首帖 `td.t_msgfont`（`id="postmessage_<pid>"`）—— 当前全局模板
    /// - WAP：首帖 `div.detailcon`、回复 `div.replycon`
    /// 按「PC 首帖 → WAP 首帖 → WAP 回复」取第一个可用块。
    /// - Parameter limit: 截断字数（默认 120，首页 3 行足够）。
    static func parsePreviewText(from html: String, limit: Int = 120) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            let pcFirst = try doc.select("td.t_msgfont").first()
                ?? doc.select("[id^=postmessage_]").first()
            let wapFirst = try doc.select("div.detailcon").first()
            let wapReply = try doc.select("div.replycon").first()
            guard let block = pcFirst ?? wapFirst ?? wapReply else { return nil }
            var text = try block.text()
            text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return text.count > limit ? String(text.prefix(limit)) + "…" : text
        } catch {
            return nil
        }
    }

    // MARK: - 附件检测

    /// 检测正文是否含有「附件」（文件型）。
    /// 依据真实 4D4Y 结构防御性实现：下载型附件通常表现为
    /// `<a href="attachment.php?aid=NNN">…</a>`，或残留 `[attach]` / `[attachimg]` BBCode；
    /// 图片型附件已在 `parseContentImageURLs` 中识别为内容图（hasImage）。
    /// 真实附件样本缺失，需在真机复核（见交付说明）。
    static func detectHasAttachment(from html: String) -> Bool {
        let lower = html.lowercased()
        return lower.contains("attachment.php?aid=") || lower.contains("[attach")
    }

    // MARK: - 提取 <img> 的 src / file 属性

    /// 收集所有 <img> 标签内的图片地址（每个 `<img>` 只取一个）。
    /// - 优先取 `file`（Discuz 常用作原图地址），否则取 `src`（缩略图）；
    /// - 这样同一张图的 `src`+`file` 不会重复计数。
    /// 关键：必须先圈定 `<img ...>` 标签，再在标签内取值，
    /// 否则会误匹配 `<script src=...>` / `<link>` / Cloudflare challenge 脚本等非图片资源。
    private static func allImageSources(in html: String) -> [String] {
        guard let tagRe = try? NSRegularExpression(
            pattern: #"<img\b[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let tags = tagRe.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var out: [String] = []
        for t in tags {
            let tag = (html as NSString).substring(with: t.range)
            if let file = Self.values(of: "file", in: tag).first, !file.isEmpty {
                out.append(file)
            } else if let src = Self.values(of: "src", in: tag).first, !src.isEmpty {
                out.append(src)
            }
        }
        return out
    }

    private static func values(of attribute: String, in html: String) -> [String] {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: attribute)
            + #"=["']([^"']+)["']"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let matches = re.matches(in: html, range: NSRange(html.startIndex..., in: html))
        return matches.compactMap { (html as NSString).substring(with: $0.range(at: 1)) }
    }

    // MARK: - URL 规整

    private static let base = URL(string: "https://www.4d4y.com/forum/")!

    /// 把可能相对的 src 规整为绝对 URL。
    private static func resolve(_ src: String) -> URL? {
        let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let abs = URL(string: trimmed), abs.scheme != nil { return abs }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }

    // MARK: - 过滤规则

    /// 拒绝列表：头像 / 表情 / 图标 / 模板资源（基于真实 4D4Y HTML 关键词）。
    ///
    /// `images/attachicons`、`images/group`、`images/avatars` 三项是 PC 模板特有的噪声
    /// （PC 页 `<img>` 数量约为 WAP 的 10 倍以上），此前在实测探查中已确认属于模板资源。
    private static let excludedKeywords: [String] = [
        "uc_server/data/avatar",   // 作者头像
        "images/avatars",          // 头像（PC 模板另一路径）
        "images/smilies",          // 表情
        "smilies",                 // 表情（别名）
        "images/icons",            // 类型 / 状态图标
        "images/attachicons",      // 附件类型小图标（PC 模板）
        "images/group",            // 用户组图标（PC 模板）
        "images/default",          // 模板“赞/踩”等图标（agree.gif 等）
        "templates/",              // 模板资源（logo / fuser 等）
        "images/common",           // 通用模板图标（PC 附件图的 none.gif 占位在此）
        "css/", "static/",         // 样式 / 静态资源
        ".js", ".css", ".woff", ".woff2",  // 脚本 / 样式 / 字体（绝不应作为图片）
        "challenge-platform", "cloudflare", // 拦截页脚本（防御性）
        "logo", "fuser", "agree", "emotion", "emot", "face", "icon" // 模板/表情词
    ]

    /// 该 URL 是否命中拒绝列表（任一关键词即排除）。
    private static func isExcluded(_ lowercased: String) -> Bool {
        excludedKeywords.contains { lowercased.contains($0) }
    }

    /// 是否「真实内容图片」候选。
    ///
    /// ⚠️ **不要求图片必须托管在 4d4y.com**：老帖（2004–2006）的配图大量存放在当年的
    /// 第三方图床（实测 tid=332225 首帖 4 张图全在 `pic.eawan.com`；tid=332225 的附件图
    /// 则在 `img02.4d4y.com`）。限定同域会把外链那一批整批丢掉。
    /// 改判据为「**不在噪声列表内的 http(s) 图片**」—— 模板 / 表情 / 头像 / 图标都在同一
    /// 站点上，已由 `excludedKeywords` 拦住；正文里的外链基本就是作者贴的内容图。
    private static func isContentImage(_ lowercased: String) -> Bool {
        guard lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") else { return false }
        guard !isExcluded(lowercased) else { return false }
        guard !adKeywords.contains(where: { lowercased.contains($0) }) else { return false }
        return true
    }

    /// 明显的广告 / 统计像素域名（防御性排黑，不是白名单）。
    private static let adKeywords: [String] = [
        "doubleclick", "googlesyndication", "google-analytics", "googleadservices",
        "adservice", "/ads/", "ad_banner", "banner_ad", "spacer.gif",
    ]
}
