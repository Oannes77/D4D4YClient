import Foundation
import SwiftSoup

/// 解析 viewthread.php 帖子详情页（**两套模板都认**）。
///
/// **PC 模板**（全局默认；已用 `tid=193033` 真实页面验证，50 楼全部命中）：
/// ```
/// <table id="pid1863080">
///   <tr>
///     <td class="postauthor">
///       <div class="postinfo"><a href="space.php?uid=1142">EC</a></div>
///       <div class="popupmenu_popup userinfopanel" id="userinfo1863080">…</div>
///     </td>
///     <td class="postcontent">
///       <div class="postinfo">
///         <strong><a id="postnum1863080" href="javascript:;"><em>1</em><sup>#</sup></a></strong>
///       </div>
///       <div class="authorinfo"><em id="authorposton1863080">发表于 2004-7-22 00:42</em>
///         | …收藏…分享…只看该作者…</div>
///       <div class="defaultpost">
///         <div class="postmessage firstpost">        ← 一楼才有 firstpost
///           <div id="threadtitle"><h1><a>[心得技巧]</a> 标题</h1></div>
///           <div class="t_msgfontfix">
///             <table><tr><td class="t_msgfont" id="postmessage_1863080">正文 HTML</td></tr></table>
///           </div>
///         </div>
///       </div>
///     </td>
///   </tr>
/// </table>
/// ```
/// 被屏蔽楼层没有 `td.t_msgfont`，只有
/// `<div class="locked">提示: <em>作者被禁止或删除 内容自动屏蔽</em></div>` —— 仍按合法楼层处理。
///
/// **WAP 模板**（兜底）：`div.detail` + `li[id^=pid]`，见 `parseWAPFirstPost` / `parseWAPReply`。
///
/// 实现要点：PC 侧**以 `a[id^=postnum]`（每楼一个）为锚点**往上找所属 `<table>`，
/// 因此屏蔽楼（无正文格）同样能被列出来，不会因选择器只认 `td.t_msgfont` 而丢楼。
struct ThreadDetailParser {

    enum DetailParseError: Error {
        /// 页面上既没有 PC 楼层也没有任何 WAP 楼层（Selector 未匹配或模板改版）
        case noPostNodes
    }

    static func parse(html: String) throws -> ThreadPage {
        let document = try SwiftSoup.parse(html)

        if let page = parsePC(document: document) { return page }
        Log.parser.warning("PC 模板未命中楼层，回退 WAP 模板解析")
        return try parseWAP(document: document)
    }

    // MARK: - PC 模板

    private static func parsePC(document: Document) -> ThreadPage? {
        let anchors = (try? document.select("a[id^=postnum]")) ?? Elements()
        guard anchors.size() > 0 else { return nil }

        let (title, typeName) = parsePCTitle(document: document)

        var posts: [Post] = []
        for anchor in anchors.array() {
            if let post = parsePCPost(anchor) { posts.append(post) }
        }
        guard !posts.isEmpty else { return nil }

        // ⚠️ os.Logger 的插值在编译期被转成 `OSLogMessage`，**不支持 `+` 拼接**，
        // 所以先把要打印的量算成本地常量，再一次性写进一条消息里。
        let blockedCount = posts.filter(\.isBlocked).count
        Log.parser.info("ThreadDetailParser(PC): \(posts.count, privacy: .public) 楼，含屏蔽楼 \(blockedCount)")
        let pageInfo = PaginationParser.parse(document: document)
            ?? PageInfo(currentPage: 1, totalPages: 1, previousPageURL: nil, nextPageURL: nil)
        return ThreadPage(title: title, typeName: typeName, posts: posts, pageInfo: pageInfo)
    }

    /// 标题：`div#threadtitle h1`，文本形如 `[心得技巧] 真实标题`。
    private static func parsePCTitle(document: Document) -> (String, String?) {
        guard let h1 = (try? document.select("div#threadtitle h1").first()) ?? nil,
              let raw = try? h1.text(), !raw.isEmpty else { return ("", nil) }
        if let groups = raw.capturedGroups(2, pattern: #"^\[([^\]]+)\]\s*(.+)$"#) {
            return (groups[1], groups[0])
        }
        return (raw, nil)
    }

    private static func parsePCPost(_ anchor: Element) -> Post? {
        // 所属楼层容器：从楼层号锚点往上找最近的 <table>
        let container = anchor.parents().array().first { $0.tagName() == "table" }

        // 作者
        var authorName = "匿名"
        var authorID: Int?
        if let container,
           let link = (try? container.select("td.postauthor div.postinfo > a").first()) ?? nil {
            authorName = ((try? link.text()) ?? authorName).trimmingCharacters(in: .whitespacesAndNewlines)
            authorID = uid(from: (try? link.attr("href")) ?? "")
        }

        // 楼层号：`<a id="postnum…"><em>1</em><sup>#</sup></a>`
        var floor: Int?
        if let emText = (try? anchor.select("em").first()?.text()) ?? nil {
            floor = Int(emText.trimmingCharacters(in: .whitespaces))
        }

        // 时间
        var createdAtRaw = ""
        if let container,
           let em = (try? container.select("em[id^=authorposton]").first()) ?? nil {
            createdAtRaw = ((try? em.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // pid：优先楼层号锚点，其次正文格 id
        var realPID = pid(fromPostNumID: anchor.id())

        // 正文
        var htmlContent = ""
        var isBlocked = false
        if let container,
           let msg = (try? container.select("td.t_msgfont[id^=postmessage_]").first()) ?? nil {
            if realPID == nil { realPID = pid(fromPostMessageID: msg.id()) }
            htmlContent = (try? msg.html()) ?? ""

            // PC 模板把附件图放在与正文同级的 `div.postattachlist` 里（**不在** `td.t_msgfont` 内），
            // 并且真实地址写在 `file` 属性上（`src` 只是占位 `images/common/none.gif`）。
            // 这里把它们的真实地址以标准 `<img>` 追加到正文末尾，供上层的图片区提取显示；
            // 正文本身保持干净（不含标题块与附件文件名列表）。
            let attachImgs = (try? container.select("div.postattachlist img[file]"))?.array() ?? []
            for img in attachImgs {
                guard let file = try? img.attr("file"), !file.isEmpty else { continue }
                htmlContent += "\n<img src=\"\(file)\" alt=\"附件图\" />"
            }
        }
        if htmlContent.isEmpty {
            isBlocked = true
            if let container,
               let locked = (try? container.select("div.locked").first()) ?? nil,
               let lockedText = try? locked.text(), !lockedText.isEmpty {
                htmlContent = lockedText
            } else {
                htmlContent = "提示: 作者被禁止或删除 内容自动屏蔽"
            }
        }

        // 文件型附件（rar / zip / pdf…）。
        // 图片附件已经在上面进了正文图片网格，`AttachmentParser` 会主动跳过 `attachimg` 那些，
        // 否则同一张图会在「正文图片」与「附件」两处各出现一次。
        let attachments = container.map { AttachmentParser.parse(container: $0) } ?? []

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
                    isBlocked: isBlocked,
                    attachments: attachments)
    }

    // MARK: - WAP 模板（兜底）

    private static func parseWAP(document: Document) throws -> ThreadPage {
        // ---- 标题与分类前缀 ----
        var title = ""
        var typeName: String?
        if let h2 = try? document.select("div.detail h2").first(),
           let raw = try? h2.text() {
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
            posts.append(parseWAPFirstPost(first))
        }

        // ---- 回复楼 ----
        let replyNodes = try document.select("li[id^=pid]")
        for node in replyNodes.array() {
            posts.append(parseWAPReply(node))
        }

        guard !posts.isEmpty else {
            Log.parser.fault("Selector 未匹配任何楼层（PC 与 WAP 都不命中）")
            throw DetailParseError.noPostNodes
        }
        Log.parser.info("ThreadDetailParser(WAP): \(posts.count, privacy: .public) 楼")

        let pageInfo = PaginationParser.parse(document: document)
            ?? PageInfo(currentPage: 1, totalPages: 1, previousPageURL: nil, nextPageURL: nil)
        return ThreadPage(title: title, typeName: typeName, posts: posts, pageInfo: pageInfo)
    }

    private static func parseWAPFirstPost(_ block: Element) -> Post {
        let sub = (try? block.select("div.sub").first()) ?? nil

        var authorName = "匿名"
        var authorID: Int?
        if let sub,
           let authorLink = try? sub.select("a[href*='space.php?uid=']").first() {
            authorName = (try? authorLink.text()) ?? authorName
            authorID = Self.uid(from: (try? authorLink.attr("href")) ?? "")
        }

        var createdAtRaw = ""
        if let sub,
           let em = try? sub.select("em[id^=authorposton]").first() {
            createdAtRaw = (try? em.text()) ?? ""
        }

        var realPID: Int?
        var htmlContent = ""
        var isBlocked = false
        if let con = try? block.select("div.detailcon").first() {
            realPID = Self.pid(fromID: con.id())
            htmlContent = (try? con.html()) ?? ""
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

    private static func parseWAPReply(_ li: Element) -> Post {
        let realPID = Self.pid(fromID: li.id())

        let top = (try? li.select("div.replytop").first()) ?? nil
        let fullTopText = (try? top?.text()) ?? ""

        var authorName = "匿名"
        var authorID: Int?
        if let top,
           let authorLink = try? top.select("a[href*='space.php?uid=']").first() {
            authorName = (try? authorLink.text()) ?? authorName
            authorID = Self.uid(from: (try? authorLink.attr("href")) ?? "")
        }

        var floor: Int?
        if let f = fullTopText.capturedGroup(1, pattern: #"(\d+)\s*#"#) {
            floor = Int(f)
        }

        let createdAtRaw = fullTopText.capturedGroup(
            1, pattern: #"/\s*(\d{4}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{2})?)"#) ?? ""

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

    /// "postnum1863084" -> 1863084
    private static func pid(fromPostNumID id: String) -> Int? {
        guard id.hasPrefix("postnum") else { return nil }
        return Int(id.dropFirst(7))
    }

    /// "postmessage_1863084" -> 1863084
    private static func pid(fromPostMessageID id: String) -> Int? {
        guard id.hasPrefix("postmessage_") else { return nil }
        return Int(id.dropFirst("postmessage_".count))
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
