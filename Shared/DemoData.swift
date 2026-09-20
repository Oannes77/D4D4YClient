import Foundation
import SwiftData
import SwiftSoup

/// 离线演示数据：仅 `-DemoMode` 下使用，把真实解析夹具与样例 SwiftData 注入界面，
/// 让 Codemagic 截图能呈现「有内容」的真实组件（头像 / 📷 / 📎 / 楼层布局），无需联网。
///
/// 复用既有 Parser（`ThreadListParser` / `ThreadDetailParser`）解析仓库内夹具，
/// 不触碰任何网络 / Repository / Authentication 逻辑。
enum DemoData {

    // MARK: - 样例模型

    /// 帖子详情 Tab 使用的样例主题（真实 tid 与夹具对应）。
    /// 帖子详情 Demo 使用的样例主题，标题与 `viewthread_tid193033_page1.html` 夹具保持一致，
    /// 避免首页点进来后导航栏标题与正文内容出现明显错位。
    /// 帖子详情 Demo 使用的样例主题，标题与 `viewthread_tid193033_page1.html` 夹具保持一致，
    /// 避免首页点进来后导航栏标题与正文内容出现明显错位。
    static let sampleThread = ForumThread(
        id: 193033,
        title: "[心得技巧] Hi-pda PPC有关精华贴汇总，初学者和疑惑者进06年7月",
        typeName: "[心得技巧]",
        authorName: "EC",
        authorID: 1142,
        createdAt: nil,
        createdAtRaw: "2004-7-22 00:42",
        replies: 36,
        views: nil,
        lastReplyUserName: "EC",
        lastReplyAtRaw: "2004-7-22 00:44"
    )

    /// 图片预览 Tab 使用的本地样例图（随 App 打包，无需联网即可加载）。
    static var sampleImageURL: URL? {
        Bundle.main.url(forResource: "demo_sample", withExtension: "png")
    }

    // MARK: - 夹具解析（离线）

    /// 解析仓库内 `forumdisplay_fid14_page1.html` 得到主题列表页。
    static func loadForumDisplayFixture() -> ThreadListPage? {
        guard let url = Bundle.main.url(forResource: "forumdisplay_fid14_page1", withExtension: "html"),
              let data = try? Data(contentsOf: url) else { return nil }
        let html = String(data: data, encoding: String.Encoding(rawValue: 2147485234))
            ?? String(data: data, encoding: .utf8) ?? ""
        return try? ThreadListParser.parse(html: html)
    }

    /// 解析仓库内 `viewthread_tid193033_page1.html` 得到帖子详情页。
    /// 与论坛真实规则一致：第一页 = 首帖 + 最多 49 条回复（共 50 楼），再往下走翻页。
    /// Demo 正文已用 SwiftUI Text 同步渲染（高度首帧确定），50 楼不会阻塞主线程。
    static func loadViewthreadFixture() -> ThreadPage? {
        guard let url = Bundle.main.url(forResource: "viewthread_tid193033_page1", withExtension: "html"),
              let data = try? Data(contentsOf: url) else { return nil }
        let html = String(data: data, encoding: String.Encoding(rawValue: 2147485234))
            ?? String(data: data, encoding: .utf8) ?? ""
        guard let page = try? ThreadDetailParser.parse(html: html) else { return nil }
        let posts = Array(page.posts.prefix(50))
        return ThreadPage(title: page.title, typeName: page.typeName, posts: posts, pageInfo: page.pageInfo)
    }

    // MARK: - SwiftData 样例种子

    /// 为首页 / 板块列表 / 列表媒体标识注入离线样例数据。
    @MainActor
    static func seed(context: ModelContext) {
        // 常用板块（首页板块切换条）：与真实 fid 一致（Discovery=2 / Buy&Sell=6 / Geek Talks=7）
        for f in [("Discovery", 2), ("Buy & Sell 交易服务区", 6), ("Geek Talks 奇客怪谈", 7)] {
            PinnedForum.pin(fid: f.1, name: f.0, context: context)
        }
        // 最近浏览（首页「最近浏览」）
        for h in [("Hi-pda PPC有关精华贴汇总，初学者和疑惑者进06年7月", 193033),
                  ("PETG 打印温度到底设多少", 188120)] {
            ReadHistory.record(tid: h.1, title: h.0, forumID: 14, context: context)
        }
        // 最近访问板块（首页「最近访问板块」）
        for v in [("技术交流", 14), ("模型下载", 20)] {
            VisitedForum.record(fid: v.1, name: v.0, context: context)
        }
        // 阅读设置单例：缺省时补一条默认值，
        // 避免「阅读设置」页因查不到 LocalSettings 而显示「设置未初始化」占位。
        let settingsDescriptor = FetchDescriptor<LocalSettings>(predicate: #Predicate { $0.slot == "singleton" })
        if (try? context.fetchCount(settingsDescriptor)) == 0 {
            context.insert(LocalSettings())
        }

        // 收藏改为**论坛服务器收藏**（`my.php?item=favorites&type=thread`），
        // Demo 下的样例列表由 `FavoritesStore.refresh()` 通过 `favoritesDemo()` 提供，
        // 因此这里不再往本地 `SavedThread` 写任何数据。
        // 黑名单样例（我的 → 黑名单）：仅本机生效，演示数据不涉及真实用户。
        BlockedUser.block(uid: 9527, username: "灌水机器人", context: context)
        // 再屏蔽一位 **demo 主题流里真实存在** 的作者，这样首页 / 板块列表
        // 能直接看到「-已拉黑-」占位的实际效果（用于截图验收）。
        BlockedUser.block(uid: 888, username: "Discovery控", context: context)
        try? context.save()
    }

    /// 本地收藏演示条目（tid 与真实主题对应）。
    private static let savedThreadSamples: [(tid: Int, title: String, board: String, author: String)] = [
        (188120, "PETG 打印温度到底设多少？总拉丝", "Discovery", "Kepler"),
        (190455, "收了台 Palm Treo 650，键盘手感绝了", "Discovery", "Discovery控")
    ]

    /// 演示用「服务器收藏」列表（离线样例，仅 Demo / 截图模式使用）。
    ///
    /// 注意：这是**演示数据**，只在 `DemoMode.isOn` 时由 `FavoritesStore` 使用；
    /// 正式运行时收藏一律来自论坛服务器（`my.php?item=favorites&type=thread`）。
    static func favoritesDemo() -> [FavoriteItem] {
        savedThreadSamples.map {
            FavoriteItem(tid: $0.tid, title: $0.title, detail: "\($0.board) · \($0.author)")
        }
    }

    /// 为帖子列表行注入 📷 / 📎 媒体标识（跳过网络检测，直接按 tid 标记）。
    @MainActor
    static func seedMedia(for threads: [ForumThread], context: ModelContext) {
        guard threads.count >= 2 else { return }
        let imageInfo = ThreadMediaInfo(
            tid: threads[0].id,
            hasImage: true,
            previewImageURL: URL(string: "https://img02.4d4y.com/forum/uc_server/data/avatar/000/00/00/001_avatar_big.jpg"),
            hasAttachment: false
        )
        let attachmentInfo = ThreadMediaInfo(
            tid: threads[1].id,
            hasImage: false,
            previewImageURL: nil,
            hasAttachment: true
        )
        ThreadMediaCache.upsert(imageInfo, context: context)
        ThreadMediaCache.upsert(attachmentInfo, context: context)
    }

    // MARK: - 首页信息流样例（Threads 风格卡片）

    /// 首页 Discovery 板块主题流样例：含标题 / 预览正文 / 单图 / 附件 / 统计，
    /// 供首页卡片渲染（不触发网络）。真实模式将由 `forumdisplay` 解析 + 媒体感知合并替代。
    static func homeFeedDemo() -> [HomeThreadItem] {
        [
            HomeThreadItem(
                id: 193033,
                boardName: "Discovery",
                title: "[心得技巧] Hi-pda PPC有关精华贴汇总，初学者和疑惑者进06年7月",
                authorName: "EC",
                authorID: 1142,
                authorGroup: "论坛元老",
                previewBody: "以前ch4chen曾经编制过一篇hi-pda中PPC精华贴的汇总，但是上次网难以后，所有链接失效了，最近下定决心，重新将16页、每页40条、共约600条精华贴全部翻了出来。",
                createdAtRaw: "2 小时前",
                replies: 36,
                shares: 12,
                favorites: 48,
                points: 1520,
                views: 3820,
                hasImage: true,
                imageURL: URL(string: "https://placehold.co/600x400/534AB7/FFFFFF/png?text=PPC+Essentials"),
                hasAttachment: false,
                attachmentCount: 0
            ),
            // ⚠️ 顺序有讲究：这条的作者 `Discovery控`(uid 888) 在 `seed()` 里被本地拉黑，
            // 首页应该渲染成「-已拉黑-」占位。放在**第 2 条**是为了让它落在首屏内
            // —— 第 1 条带大图很高，占满首屏，放第 3 条就会被挤到屏幕外，截图验收看不到。
            HomeThreadItem(
                id: 190455,
                boardName: "Discovery",
                title: "[晒物] 收了台 Palm Treo 650，键盘手感绝了",
                authorName: "Discovery控",
                authorID: 888,
                authorGroup: "论坛元老",
                previewBody: "eBay 淘的 Treo 650 到货，键盘回弹比现代触屏舒服太多。刷了最新的 ROM，还能上 GPRS。复古 PDA 真香，准备写个长期把玩帖。",
                createdAtRaw: "昨天",
                replies: 102,
                shares: 41,
                favorites: 220,
                points: 5310,
                views: 12030,
                hasImage: true,
                imageURL: URL(string: "https://placehold.co/600x400/8F86E8/FFFFFF/png?text=Palm+Treo+650"),
                hasAttachment: false,
                attachmentCount: 0
            ),
            HomeThreadItem(
                id: 188120,
                boardName: "Discovery",
                title: "[求助] PETG 打印温度到底设多少？总拉丝",
                authorName: "Kepler",
                authorID: 2077,
                authorGroup: "高级会员",
                previewBody: "换了卷新 PETG，255℃ 还是拉丝严重，底板 65℃。是不是料太潮了？大家 PETG 一般怎么存，有没有推荐的烘干参数。",
                createdAtRaw: "5 小时前",
                replies: 23,
                shares: 3,
                favorites: 8,
                points: 430,
                views: 1290,
                hasImage: false,
                imageURL: nil,
                hasAttachment: true,
                attachmentCount: 2
            ),
            HomeThreadItem(
                id: 191200,
                boardName: "Discovery",
                title: "[讨论] 你们现在还用 SD 卡存 Gcode 吗",
                authorName: "麦客爱苹果",
                authorID: 522,
                authorGroup: "中级会员",
                previewBody: "现在基本都走 WiFi/OctoEverywhere 了，SD 卡反而容易丢文件。但断网的时候还是物理卡稳，纠结要不要保留这个习惯。",
                createdAtRaw: "昨天",
                replies: 17,
                shares: 1,
                favorites: 5,
                points: 210,
                views: 760,
                hasImage: false,
                imageURL: nil,
                hasAttachment: false,
                attachmentCount: 0
            )
        ]
    }

    // MARK: - 消息 / 用户卡样例（截图用离线内容，真实模式走 pm.php / space.php）

    /// 站内短信收件箱样例。
    static func pmInboxDemo() -> [PrivateMessage] {
        [
            PrivateMessage(id: "pm:uid:1024", pmid: nil, userID: 1024, userName: "老橡树",
                           subject: "你那台 X1C 的进料轮换了吗？",
                           preview: "换了第三方硅胶轮，异响基本没了。",
                           timeRaw: "昨天 21:04", isUnread: true),
            PrivateMessage(id: "pm:uid:2077", pmid: nil, userID: 2077, userName: "Kepler",
                           subject: "PETG 烘干参数收到了，谢谢！",
                           preview: "按你给的 65℃ / 4h 烘完，拉丝确实好多了。",
                           timeRaw: "昨天", isUnread: false),
            PrivateMessage(id: "pm:uid:888", pmid: nil, userID: 888, userName: "Discovery控",
                           subject: "你那台 Treo 650 出吗？想要",
                           preview: "成色好的话我收一台当收藏。",
                           timeRaw: "3 天前", isUnread: false)
        ]
    }

    /// 系统消息样例（无会话对象，列表只读展示）。
    static func systemMessagesDemo() -> [PrivateMessage] {
        [
            PrivateMessage(id: "sys:1", pmid: nil, userID: nil, userName: "系统消息",
                           subject: "回复提醒",
                           preview: "老橡树 回复了你的主题《PETG 打印温度到底设多少？》",
                           timeRaw: "2 小时前", isUnread: true),
            PrivateMessage(id: "sys:2", pmid: nil, userID: nil, userName: "系统消息",
                           subject: "收藏提醒",
                           preview: "有人收藏了你的帖子",
                           timeRaw: "昨天", isUnread: false)
        ]
    }

    /// 与「老橡树」的私信往来样例。
    static func pmConversationDemo() -> [PMBubble] {
        [
            PMBubble(id: "demo-1", text: "你那台 X1C 的进料轮换了吗？", timeRaw: "昨天 21:04", isMe: false, senderName: "老橡树"),
            PMBubble(id: "demo-2", text: "换了第三方硅胶轮，异响基本没了。", timeRaw: "昨天 21:10", isMe: true, senderName: "演示用户"),
            PMBubble(id: "demo-3", text: "太好了，我也下单一个，扭矩按多少拧？", timeRaw: "昨天 21:12", isMe: false, senderName: "老橡树"),
            PMBubble(id: "demo-4", text: "手感紧就行，别超过 0.4N·m，塑料件容易滑丝。", timeRaw: "昨天 21:15", isMe: true, senderName: "演示用户"),
            PMBubble(id: "demo-5", text: "收到，谢啦！", timeRaw: "今天 09:02", isMe: false, senderName: "老橡树")
        ]
    }

    /// 用户卡样例资料（仅截图用；真实模式走 space.php）。
    static func userProfileDemo(uid: Int, name: String) -> UserProfile {
        if uid == 1024 {
            return UserProfile(uid: 1024, name: "老橡树", group: "论坛元老",
                               posts: 328, points: 9520,
                               signature: "键盘会老，手感永存。",
                               registeredRaw: "2003-05-18", location: "上海")
        }
        return UserProfile(uid: uid, name: name.isEmpty ? "该用户" : name,
                           group: "论坛会员", posts: nil, points: nil,
                           signature: nil, registeredRaw: nil, location: nil)
    }

    // MARK: - 我的中心（my.php）样例

    /// 「我的」宫格四栏的离线样例（仅截图用；真实模式走 `my.php`）。
    ///
    /// 「关注」刻意返回 `.sectionMissing`：4D4Y 用的是 Discuz! 7.2，它的「我的中心」
    /// 没有「关注」栏目。演示数据**不假装有**，与真实模式的判断保持同一口径。
    static func mySpaceDemo(kind: MySpaceKind) -> Result<[MySpaceEntry], MySpaceError> {
        switch kind {
        case .threads:
            return .success([
                MySpaceEntry(id: "thread:193033",
                             title: "Hi-pda PPC有关精华贴汇总，初学者和疑惑者进 06 年 7 月",
                             detail: "Discovery · 36 回复",
                             timeRaw: "2004-7-22 00:42",
                             threadID: 193033, userID: nil, userName: nil),
                MySpaceEntry(id: "thread:188120",
                             title: "PETG 打印温度到底设多少？总拉丝",
                             detail: "Discovery · 23 回复",
                             timeRaw: "昨天 14:05",
                             threadID: 188120, userID: nil, userName: nil),
                MySpaceEntry(id: "thread:190455",
                             title: "收了台 Palm Treo 650，键盘手感绝了",
                             detail: "Discovery · 102 回复",
                             timeRaw: "3 天前",
                             threadID: 190455, userID: nil, userName: nil)
            ])
        case .replies:
            return .success([
                MySpaceEntry(id: "thread:193033",
                             title: "Re: Hi-pda PPC有关精华贴汇总，初学者和疑惑者进 06 年 7 月",
                             detail: "Discovery · 我的回复在第 12 楼",
                             timeRaw: "今天 09:12",
                             threadID: 193033, userID: nil, userName: nil),
                MySpaceEntry(id: "thread:188120",
                             title: "Re: PETG 打印温度到底设多少？总拉丝",
                             detail: "Discovery · 我的回复在第 4 楼",
                             timeRaw: "昨天 20:31",
                             threadID: 188120, userID: nil, userName: nil)
            ])
        case .friends:
            return .success([
                MySpaceEntry(id: "user:1024", title: "老橡树", detail: "论坛元老 · UID 1024",
                             timeRaw: "", threadID: nil, userID: 1024, userName: "老橡树"),
                MySpaceEntry(id: "user:2077", title: "Kepler", detail: "高级会员 · UID 2077",
                             timeRaw: "", threadID: nil, userID: 2077, userName: "Kepler"),
                MySpaceEntry(id: "user:888", title: "Discovery控", detail: "论坛元老 · UID 888",
                             timeRaw: "", threadID: nil, userID: 888, userName: "Discovery控")
            ])
        case .follows:
            // 本站没有这个栏目：演示数据与真实判断一致，不凭空造一份列表。
            return .failure(.sectionMissing(kind.title))
        }
    }
}
