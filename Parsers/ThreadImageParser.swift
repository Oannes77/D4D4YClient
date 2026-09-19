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
        let candidates = allImageSources(in: html)
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

    // MARK: - 首帖预览文本

    /// 解析首帖纯文本摘要（首页卡片 3 行预览用）。
    ///
    /// 与图片检测共用同一次 viewthread 请求，不额外发请求。
    /// 取「一楼正文 div.detailcon」，缺失时回退第一条回复 div.replycon。
    /// - Parameter limit: 截断字数（默认 120，首页 3 行足够）。
    static func parsePreviewText(from html: String, limit: Int = 120) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            let firstBlock = try doc.select("div.detailcon").first()
            let block = firstBlock ?? (try doc.select("div.replycon").first())
            guard let block else { return nil }
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
    private static let excludedKeywords: [String] = [
        "uc_server/data/avatar",   // 作者头像
        "images/smilies",          // 表情
        "smilies",                 // 表情（别名）
        "images/icons",            // 类型 / 状态图标
        "images/default",          // 模板“赞/踩”等图标（agree.gif 等）
        "templates/",              // 模板资源（logo / fuser 等）
        "images/common",           // 通用模板图标
        "css/", "static/",         // 样式 / 静态资源
        ".js", ".css", ".woff", ".woff2",  // 脚本 / 样式 / 字体（绝不应作为图片）
        "challenge-platform", "cloudflare", // 拦截页脚本（防御性）
        "logo", "fuser", "agree", "emotion", "emot", "face", "icon" // 模板/表情词
    ]

    /// 该 URL 是否命中拒绝列表（任一关键词即排除）。
    private static func isExcluded(_ lowercased: String) -> Bool {
        excludedKeywords.contains { lowercased.contains($0) }
    }

    /// 是否「真实内容图片」候选：
    /// 1) 必须属于 4D4Y 论坛域（排除外链广告图）；
    /// 2) 不在拒绝列表内；
    /// 3) 优先识别 img02 CDN 内容图；相对路径含 attachment/data 也接受。
    private static func isContentImage(_ lowercased: String) -> Bool {
        guard lowercased.contains("4d4y.com") else { return false }
        guard !isExcluded(lowercased) else { return false }
        // 内容图通常位于 img02 CDN 或附件路径
        if lowercased.contains("img02.4d4y.com/forum/") { return true }
        if lowercased.contains("attachment") || lowercased.contains("data/") { return true }
        // 同域其它图片（已排除模板/表情/头像）保守接受
        return true
    }
}
