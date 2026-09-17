import Foundation
import SwiftSoup

/// 解析 viewthread.php 帖子详情页。
///
/// 真实 DOM（Discuz! 7.2 + 定制 wap 模板，已用 tid=193033 第 1/2 页验证）：
///
/// 一楼（只有第 1 页有）：
/// ```
/// <div class="w bordertop detail">
///   <h2><a ...>[心得技巧]</a> Hi-pda PPC有关精华贴汇总...</h2>
///   <div class="sub"><a href="space.php?uid=1142">EC</a>
///     <em id="authorposton1863080">发表于 2004-7-22 00:42</em></div>
///   <div class="detailcon" id="pid1863080">正文 HTML ...</div>
/// </div>
/// ```
///
/// 回复楼（<ul> 内的每个 <li>）：
/// ```
/// <li id="pid1863084">
///   <div class="replytop"><span></span>2#</span><a href="space.php?uid=1142">EC</a>/ 2004-7-22 00:44 </div>
///   <div class="replycon">正文 HTML ...</div>
/// </li>
/// ```
///
/// 特殊情况：内容被屏蔽的楼层只有 <div class="locked">提示: 作者被禁止或删除…</div>，
/// 没有 replycon —— 必须按合法楼层处理。
struct ThreadDetailParser {

    enum DetailParseError: Error {
        /// 页面上既没有一楼也没有任何回复楼（Selector 未匹配或模板改版）
        case noPostNodes
    }

    static func parse(html: String) throws -> ThreadPage {
        let document = try SwiftSoup.parse(html)

        // ---- 标题与分类前缀 ----
        var title = ""
        var typeName: String?
        if let h2 = try? document.select("div.detail h2").first(),
           let raw = try? h2.text() {
            // 分类前缀形如 "[心得技巧] 真实标题"。用 NSRegularExpression（跨 Swift 版本稳定、
            // 易单测）提取两个捕获组，不使用 Swift.String.firstMatch(of:)（其参数必须是 Regex 字面量）。
            if let groups = raw.capturedGroups(2, pattern: #"^\[([^\]]+)\]\s*(.+)$"#) {
                typeName = groups[0]
                title = groups[1]
            } else {
                title = raw
            }
        }

        var posts: [Post] = []

        // ---- 一楼 ----
        if let first = try? document.select("div.detail").first() {
            posts.append(parseFirstPost(first))
        }

        // ---- 回复楼 ----
        let replyNodes = try document.select("li[id^=pid]")
        for node in replyNodes.array() {
            posts.append(parseReply(node))
        }

        guard !posts.isEmpty else {
            Log.parser.fault("Selector 未匹配任何楼层（div.detail / li[id^=pid] 均为空）")
            throw DetailParseError.noPostNodes
        }
        Log.parser.info("ThreadDetailParser: \(posts.count, privacy: .public) 楼（含一楼=\(posts.first?.floor == 1)）")

        let pageInfo = PaginationParser.parse(document: document)
            ?? PageInfo(currentPage: 1, totalPages: 1, previousPageURL: nil, nextPageURL: nil)
        return ThreadPage(title: title, typeName: typeName, posts: posts, pageInfo: pageInfo)
    }

    // MARK: - 一楼

    private static func parseFirstPost(_ block: Element) -> Post {
        let sub = (try? block.select("div.sub").first()) ?? nil

        var authorName = "匿名"
        var authorID: Int?
        if let authorLink = try? sub?.select("a[href*='space.php?uid=']").first(), let link = authorLink {
            authorName = (try? link.text()) ?? authorName
            authorID = Self.uid(from: (try? link.attr("href")) ?? "")
        }

        var createdAtRaw = ""
        if let em = try? sub?.select("em[id^=authorposton]").first(), let e = em {
            createdAtRaw = (try? e.text()) ?? ""
        }

        var realPID: Int?
        var htmlContent = ""
        var isBlocked = false
        if let con = try? block.select("div.detailcon").first(), let c = con {
            realPID = Self.pid(fromID: (try? c.id()) ?? "")
            htmlContent = (try? c.html()) ?? ""
        }
        if htmlContent.isEmpty {
            isBlocked = true
            htmlContent = "提示: 作者被禁止或删除 内容自动屏蔽"
        }

        let id = Self.resolvePostID(realPID: realPID,
                                    floor: 1,
                                    authorName: authorName,
                                    createdAtRaw: createdAtRaw,
                                    htmlContent: htmlContent)
        return Post(id: id,
                    floor: 1,
                    authorName: authorName,
                    authorID: authorID,
                    createdAt: DiscuzDateParser.parse(createdAtRaw),
                    createdAtRaw: createdAtRaw,
                    htmlContent: htmlContent,
                    isBlocked: isBlocked)
    }

    // MARK: - 回复楼

    private static func parseReply(_ li: Element) -> Post {
        let realPID = Self.pid(fromID: (try? li.id()) ?? "")

        let top = (try? li.select("div.replytop").first()) ?? nil
        let fullTopText = (try? top?.text()) ?? ""

        // 作者
        var authorName = "匿名"
        var authorID: Int?
        if let authorLink = try? top?.select("a[href*='space.php?uid=']").first(), let link = authorLink {
            authorName = (try? link.text()) ?? authorName
            authorID = Self.uid(from: (try? link.attr("href")) ?? "")
        }

        // 楼层："2#"
        var floor: Int?
        if let f = fullTopText.capturedGroup(1, pattern: #"(\d+)\s*#"#) {
            floor = Int(f)
        }

        // 时间："/ 2004-7-22 00:44"
        var createdAtRaw = fullTopText.capturedGroup(
            1, pattern: #"/\s*(\d{4}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2})?)"#) ?? ""

        // 正文
        let con = (try? li.select("div.replycon").first()) ?? nil
        var htmlContent = (try? con?.html()) ?? ""
        var isBlocked = false
        if htmlContent.isEmpty {
            if let locked = (try? li.select("div.locked").first()) ?? nil,
               let lockedText = try? locked.text(), !lockedText.isEmpty {
                htmlContent = lockedText
            } else {
                htmlContent = "(此楼无正文)"
            }
            isBlocked = true
        }

        let id = Self.resolvePostID(realPID: realPID,
                                    floor: floor,
                                    authorName: authorName,
                                    createdAtRaw: createdAtRaw,
                                    htmlContent: htmlContent)
        return Post(id: id,
                    floor: floor,
                    authorName: authorName,
                    authorID: authorID,
                    createdAt: DiscuzDateParser.parse(createdAtRaw),
                    createdAtRaw: createdAtRaw,
                    htmlContent: htmlContent,
                    isBlocked: isBlocked)
    }

    // MARK: - 工具

    /// 真实 pid 优先；缺失时用确定性内容做 FNV-1a 哈希得到稳定唯一 id，
    /// 不依赖运行时随机种子、刷新后保持一致，避免多个失败楼层都塌成 0。
    private static func resolvePostID(realPID: Int?,
                                      floor: Int?,
                                      authorName: String,
                                      createdAtRaw: String,
                                      htmlContent: String) -> Int {
        if let pid = realPID { return pid }
        let key = "\(floor.map(String.init) ?? "-"):\(authorName):\(createdAtRaw):\(htmlContent.prefix(64))"
        var hash: UInt64 = 1469598103934665603   // FNV-1a offset basis
        let prime: UInt64 = 1099511628211
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return Int(bitPattern: UInt(hash))
    }

    /// "pid1863084" -> 1863084
    private static func pid(fromID id: String) -> Int? {
        guard id.hasPrefix("pid") else { return nil }
        return Int(id.dropFirst(3))
    }

    /// "space.php?uid=1142" -> 1142
    private static func uid(from href: String) -> Int? {
        guard let range = href.range(of: #"uid=(\d+)"#, options: .regularExpression) else { return nil }
        return Int(href[range].dropFirst(4))
    }
}

/// 基于 NSRegularExpression 的字符串捕获助手（跨 Swift 版本稳定，便于单测）。
/// 不使用 Swift.String.firstMatch(of:)，避免把普通字符串字面量误当 Regex 字面量导致编译失败。
private extension String {
    /// 返回第 `group` 个捕获组（group 从 1 起）的子串；无匹配返回 nil。
    func capturedGroup(_ group: Int, pattern: String) -> String? {
        guard group >= 1,
              let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(self.startIndex..<self.endIndex, in: self)),
              match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: self) else { return nil }
        return String(self[range])
    }

    /// 返回第 1..groupCount 个捕获组的子串数组；整体未匹配返回 nil。
    func capturedGroups(_ groupCount: Int, pattern: String) -> [String]? {
        guard groupCount >= 1,
              let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(self.startIndex..<self.endIndex, in: self)),
              match.numberOfRanges >= groupCount + 1 else { return nil }
        return (1...groupCount).compactMap { i in
            guard let r = Range(match.range(at: i), in: self) else { return nil }
            return String(self[r])
        }
    }
}
