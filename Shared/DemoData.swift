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
    static let sampleThread = ForumThread(
        id: 193033,
        title: "[心得技巧] Bambu X1C 进料轮异响排查与润滑",
        typeName: "[心得技巧]",
        authorName: "演示作者",
        authorID: 12345,
        createdAt: nil,
        createdAtRaw: "2026-09-10",
        replies: 36,
        views: nil,
        lastReplyUserName: "热心网友",
        lastReplyAtRaw: "2026-09-15"
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
    static func loadViewthreadFixture() -> ThreadPage? {
        guard let url = Bundle.main.url(forResource: "viewthread_tid193033_page1", withExtension: "html"),
              let data = try? Data(contentsOf: url) else { return nil }
        let html = String(data: data, encoding: String.Encoding(rawValue: 2147485234))
            ?? String(data: data, encoding: .utf8) ?? ""
        return try? ThreadDetailParser.parse(html: html)
    }

    // MARK: - SwiftData 样例种子

    /// 为首页 / 板块列表 / 列表媒体标识注入离线样例数据。
    @MainActor
    static func seed(context: ModelContext) {
        // 常用板块（首页「常用板块」）
        for f in [("技术交流", 14), ("模型下载", 20), ("心得技巧", 7)] {
            PinnedForum.pin(fid: f.1, name: f.0, context: context)
        }
        // 最近浏览（首页「最近浏览」）
        for h in [("Bambu X1C 进料轮异响排查与润滑", 193033),
                  ("PETG 打印温度到底设多少", 188120)] {
            ReadHistory.record(tid: h.1, title: h.0, forumID: 14, context: context)
        }
        // 最近访问板块（首页「最近访问板块」）
        for v in [("技术交流", 14), ("模型下载", 20)] {
            VisitedForum.record(fid: v.1, name: v.0, context: context)
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
                title: "[心得技巧] Bambu X1C 进料轮异响排查与润滑",
                authorName: "老橡树",
                authorID: 1024,
                authorGroup: "论坛元老",
                previewBody: "最近 X1C 打印到一半开始发出规律的「哒哒」异响，拆开进料组件发现进料轮橡胶圈有细微裂纹。换了第三方硅胶轮之后安静多了，顺便分享一下润滑点和扭矩，免得大家走弯路。",
                createdAtRaw: "2 小时前",
                replies: 36,
                shares: 12,
                favorites: 48,
                points: 1520,
                views: 3820,
                hasImage: true,
                imageURL: URL(string: "https://placehold.co/600x400/534AB7/FFFFFF/png?text=Bambu+X1C"),
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
}
