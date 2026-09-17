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
        let html = String(data: data, encoding: .gb_18030_2000)
            ?? String(data: data, encoding: .utf8) ?? ""
        return try? ThreadListParser.parse(html: html)
    }

    /// 解析仓库内 `viewthread_tid193033_page1.html` 得到帖子详情页。
    static func loadViewthreadFixture() -> ThreadPage? {
        guard let url = Bundle.main.url(forResource: "viewthread_tid193033_page1", withExtension: "html"),
              let data = try? Data(contentsOf: url) else { return nil }
        let html = String(data: data, encoding: .gb_18030_2000)
            ?? String(data: data, encoding: .utf8) ?? ""
        return try? ThreadDetailParser.parse(html: html)
    }

    // MARK: - SwiftData 样例种子

    /// 为首页 / 板块列表 / 列表媒体标识注入离线样例数据。
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
}
