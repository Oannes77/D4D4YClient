import Foundation
import SwiftSoup

/// 解析 Discuz! `my.php`（我的中心）的导航与列表页。
///
/// ⚠️ **结构未在本地验证**：`my.php` 必须登录才可达（游客实测返回
/// 「对不起，您还未登录，无法进行此操作。」+ 登录表单），而 4D4Y 用的是
/// 定制 wap 模板，桌面版与 wap 版结构可能都不完全一致。因此这里采用
/// **导航动态发现 + 通用锚点抽取**的防御式实现：
///
/// 1. 命中登录门 → `.requiresLogin`
/// 2. 列表页抽取规则（不依赖具体 class 名）：
///    - 帖子型（帖子 / 回复 / **关注**）：取指向 `viewthread.php?tid=` 的链接，**同一 tid 取文本最长的那条**当标题
///    - 用户型（好友）：取指向 `space.php?uid=` 的链接，按 uid 去重
///      ⚠️「关注」是**帖子型**：`my.php?item=attention` 关注的是主题（参数 tid），不是人。
///    - 「明细」= 链接所在容器文本剔除标题与时间后的剩余部分（版块名 / 分组等）
/// 3. 页面上完全没有目标链接 → `.empty`（**确实没有内容**，页面正常打开了）
/// 4. 有候选链接但一条都认不出 → `.unsupported`（结构未识别，界面如实说明）
///
/// 全程**绝不编造条目**。
struct MySpaceParser {

    enum Outcome {
        case entries([MySpaceEntry])
        case empty
        case requiresLogin
        case unsupported
    }

    // MARK: - 导航动态发现

    /// 解析 `my.php` 页内导航，得到「item 参数 → 栏目名」。
    ///
    /// 用于避免硬编码 `item=threads` 这类参数：站点改版换名时客户端自动跟随。
    /// 解析不到（模板过简 / 未登录）时返回空字典，调用方退回候选参数。
    static func menuItems(html: String) -> [String: String] {
        guard let doc = try? SwiftSoup.parse(html),
              let anchors = (try? doc.select("a[href*='my.php']"))?.array() else { return [:] }

        var menu: [String: String] = [:]
        for anchor in anchors {
            let href = (try? anchor.attr("href")) ?? ""
            guard let item = stringValue(in: href, pattern: #"item=([A-Za-z_]+)"#) else { continue }
            let label = PMListParser.collapseWhitespace((try? anchor.text()) ?? "")
            guard !label.isEmpty, menu[item] == nil else { continue }
            menu[item] = label
        }
        return menu
    }

    // MARK: - 列表解析

    static func parse(html: String, kind: MySpaceKind) -> Outcome {
        if PMListParser.isLoginGate(html) { return .requiresLogin }
        guard let doc = try? SwiftSoup.parse(html) else { return .unsupported }

        let selector = kind.isUserList ? "a[href*='space.php?uid=']" : "a[href*='viewthread.php']"
        let raw = ((try? doc.select(selector))?.array()) ?? []
        // 页面正常打开、连一条目标链接都没有 → 这个栏目是空的
        if raw.isEmpty { return .empty }

        let entries = kind.isUserList ? userEntries(in: doc) : threadEntries(in: doc)
        if entries.isEmpty {
            Log.parser.error("MySpaceParser[\(kind.rawValue, privacy: .public)] 抽到 \(raw.count, privacy: .public) 个链接但无有效条目（结构未识别）")
            return .unsupported
        }
        Log.parser.info("MySpaceParser[\(kind.rawValue, privacy: .public)]: \(entries.count, privacy: .public) 条")
        return .entries(entries)
    }

    /// 帖子型：`viewthread.php?tid=` 按 tid 去重，标题取同一 tid 中最长的链接文本。
    private static func threadEntries(in doc: Document) -> [MySpaceEntry] {
        let anchors = ((try? doc.select("a[href*='viewthread.php']"))?.array()) ?? []

        var order: [Int] = []
        var best: [Int: (anchor: Element, title: String)] = [:]
        for anchor in anchors {
            let href = (try? anchor.attr("href")) ?? ""
            guard let tid = PMListParser.intValue(in: href, pattern: #"tid=(\d+)"#), tid > 0 else { continue }
            let text = PMListParser.collapseWhitespace((try? anchor.text()) ?? "")
            guard !text.isEmpty else { continue }
            if best[tid] == nil { order.append(tid) }
            if let existing = best[tid], existing.title.count >= text.count { continue }
            best[tid] = (anchor, text)
        }

        var entries: [MySpaceEntry] = []
        for tid in order {
            guard let picked = best[tid] else { continue }
            let containerText = containerText(around: picked.anchor, maxDepth: 5)
            let timeRaw = PMListParser.firstDate(in: containerText) ?? ""
            entries.append(MySpaceEntry(
                id: "thread:\(tid)",
                title: picked.title,
                detail: residual(containerText, removing: [picked.title, timeRaw]),
                timeRaw: timeRaw,
                threadID: tid,
                userID: nil,
                userName: nil
            ))
        }
        return entries
    }

    /// 用户型：`space.php?uid=` 按 uid 去重，显示名取同一 uid 中最长的链接文本。
    private static func userEntries(in doc: Document) -> [MySpaceEntry] {
        let anchors = ((try? doc.select("a[href*='space.php?uid=']"))?.array()) ?? []

        var order: [Int] = []
        var best: [Int: (anchor: Element, name: String)] = [:]
        for anchor in anchors {
            let href = (try? anchor.attr("href")) ?? ""
            guard let uid = PMListParser.intValue(in: href, pattern: #"uid=(\d+)"#), uid > 0 else { continue }
            let text = PMListParser.collapseWhitespace((try? anchor.text()) ?? "")
            guard !text.isEmpty else { continue }
            if best[uid] == nil { order.append(uid) }
            if let existing = best[uid], existing.name.count >= text.count { continue }
            best[uid] = (anchor, text)
        }

        var entries: [MySpaceEntry] = []
        for uid in order {
            guard let picked = best[uid] else { continue }
            let containerText = containerText(around: picked.anchor, maxDepth: 4)
            entries.append(MySpaceEntry(
                id: "user:\(uid)",
                title: picked.name,
                detail: residual(containerText, removing: [picked.name]),
                timeRaw: "",
                threadID: nil,
                userID: uid,
                userName: picked.name
            ))
        }
        return entries
    }

    // MARK: - 结构定位

    /// 从链接向上寻找「信息比链接本身更多」的容器，作为这一条记录所在的块。
    /// 找不到时退回父节点，保证总有可用的明细文本。
    private static func containerText(around anchor: Element, maxDepth: Int) -> String {
        let ownText = PMListParser.collapseWhitespace((try? anchor.text()) ?? "")
        var node: Element? = anchor.parent()
        var depth = 0
        while let current = node, depth < maxDepth {
            let text = PMListParser.collapseWhitespace((try? current.text()) ?? "")
            if text.count > ownText.count { return text }
            node = current.parent()
            depth += 1
        }
        return PMListParser.collapseWhitespace((try? anchor.parent()?.text()) ?? ownText)
    }

    /// 容器文本剔除已知片段后剩下的内容（作为次级说明），过长则截断。
    private static func residual(_ text: String, removing tokens: [String]) -> String {
        var result = text
        for token in tokens where !token.isEmpty {
            result = result.replacingOccurrences(of: token, with: " ")
        }
        result = PMListParser.collapseWhitespace(result)
        return result.count > 70 ? String(result.prefix(70)) : result
    }

    /// 正则第 1 个捕获组的字符串值。
    private static func stringValue(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text,
                                           range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
