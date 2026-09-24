import Foundation

/// 版块（论坛分区导航）。
/// 来源：每个 Discuz! 页面自带的 #silder_l 侧边栏菜单
/// （index.php 被 Cloudflare 拦截，不能直接用它获取版块列表）。
struct ForumSection: Identifiable, Hashable {
    let id: Int          // fid
    let name: String
    let isSubForum: Bool
}

/// 版块主题列表中的一行。
/// 对应 forumdisplay.php 的 <tr> 结构。
struct ForumThread: Identifiable, Hashable {
    let id: Int                  // tid
    let title: String
    let typeName: String?        // [心得技巧] 这类分类前缀
    let authorName: String       // 匿名帖可能是 "匿名"
    let authorID: Int?           // space.php?uid=NNN；匿名/纯用户名链接时为 nil
    let createdAt: Date?         // 发帖日期（该模板只有年月日）
    let createdAtRaw: String
    let replies: Int?            // 回复数
    // 查看数：**只有 PC 模板有**（`td.nums > em`，Sprint 18 起全局走 PC 才拿到值）。
    // WAP 模板不输出，所以在 WAP 兜底解析路径下这里会是 nil —— 界面按 nil 隐藏即可。
    let views: Int?
    let lastReplyUserName: String?
    let lastReplyAtRaw: String?  // 最后回复时间
}

/// 帖子详情页的一个楼层。
struct Post: Identifiable, Hashable {
    let id: Int                  // pid（第一楼取 detailcon 的 id=pidXXX）
    let floor: Int?              // 楼层号；一楼为 1，回复楼取 "N#" 中的 N
    let authorName: String
    let authorID: Int?
    let createdAt: Date?
    let createdAtRaw: String
    /// 原始正文 HTML（保留图片/链接/引用/表情等结构，第一阶段不做富文本转换）
    let htmlContent: String
    /// 该楼内容被论坛屏蔽（div.locked：作者被禁止或删除）
    let isBlocked: Bool
}

/// 分页信息。全部由页面 HTML 推导，不写死 URL。
struct PageInfo: Hashable {
    let currentPage: Int
    let totalPages: Int
    /// 上一页的相对 URL（如 forumdisplay.php?fid=14&page=1），无则为 nil
    let previousPageURL: String?
    /// 下一页的相对 URL，无则为 nil
    let nextPageURL: String?
}

/// 版块页解析结果。
struct ThreadListPage {
    let forumName: String?
    let threads: [ForumThread]
    let pageInfo: PageInfo
}

/// 帖子页解析结果。
struct ThreadPage {
    let title: String
    let typeName: String?
    let posts: [Post]
    let pageInfo: PageInfo
}

// MARK: - 媒体感知（与 ForumThread 网络模型严格分离）

/// 主题媒体元数据（纯数据，不混入论坛网络模型）。
/// 来源：ImageMetadataRepository 请求 viewthread 第一页 → ThreadImageParser 解析正文 HTML。
/// 持久化副本见 LocalModels.ThreadMediaCache（SwiftData）。
///
/// 设计（Sprint 9B 重定义）：列表只做轻量标识，不是图片浏览系统——
/// - hasImage        : 正文存在有效内容图片；
/// - previewImageURL : 第一张有效内容图（点击 📷 预览用），无图时为 nil；
/// - hasAttachment   : 正文含附件（文件型；列表不预览，进入帖子查看）。
/// - previewText     : 首帖纯文本摘要（首页 3 行预览用，截断 120 字）；
///                     与图片同一次 viewthread 请求顺带解析，不额外增加请求。
/// 不保存图片数量 / 多缩略图 / 图墙，保持简单。
struct ThreadMediaInfo: Hashable {
    let tid: Int
    let hasImage: Bool
    /// 第一张有效正文图片的绝对 URL（点击 📷 直接预览），无图时为 nil。
    let previewImageURL: URL?
    /// 是否含附件（文件型；点击列表行进入帖子后查看）。
    let hasAttachment: Bool
    /// 首帖纯文本摘要（用于首页正文预览）。解析失败时为 nil。
    let previewText: String?

    init(tid: Int, hasImage: Bool, previewImageURL: URL?,
         hasAttachment: Bool, previewText: String? = nil) {
        self.tid = tid
        self.hasImage = hasImage
        self.previewImageURL = previewImageURL
        self.hasAttachment = hasAttachment
        self.previewText = previewText
    }
}
