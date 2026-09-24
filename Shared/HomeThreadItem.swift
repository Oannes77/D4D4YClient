import Foundation

/// 首页信息流（板块主题列表）的一行渲染模型。
///
/// 与 `ForumThread`（真实解析模型）解耦：首页需要「预览正文 / 图片 / 附件 / 统计」等列表元数据，
/// 而 Discuz `forumdisplay` 列表行本身不含正文。该结构用于首页 Threads 卡片渲染，
/// Demo 模式下由 `DemoData.homeFeedDemo()` 提供样例，真实模式由列表解析 + 媒体感知合并产生。
struct HomeThreadItem: Identifiable, Hashable {
    let id: Int                  // tid
    let boardName: String        // 板块名，如 Discovery
    let title: String
    let authorName: String
    let authorID: Int?
    let authorGroup: String?     // 分组（论坛元老 / 高级会员 ...），用于用户卡
    let previewBody: String      // 预览正文（首页 3 行截断，详情页展开全文）
    let createdAtRaw: String     // 相对/原始时间
    let replies: Int
    /// 浏览量。**PC 模板的 `td.nums > em` 会输出**（切模板前 WAP 页面没有，所以恒为 nil）。
    /// 拿不到时界面隐藏这个数字，不编一个。
    let views: Int?
    let hasImage: Bool
    let imageURL: URL?           // 第一张正文图（列表只显一张）
    let hasAttachment: Bool
    let attachmentCount: Int
}

extension HomeThreadItem {
    /// 用媒体检测结果（首图 / 附件 / 首帖摘要）更新渲染行，其余字段保持不变。
    func updated(with info: ThreadMediaInfo) -> HomeThreadItem {
        HomeThreadItem(
            id: id,
            boardName: boardName,
            title: title,
            authorName: authorName,
            authorID: authorID,
            authorGroup: authorGroup,
            previewBody: info.previewText ?? previewBody,
            createdAtRaw: createdAtRaw,
            replies: replies,
            views: views,
            hasImage: info.hasImage || hasImage,
            imageURL: info.previewImageURL ?? imageURL,
            hasAttachment: info.hasAttachment || hasAttachment,
            attachmentCount: attachmentCount
        )
    }
}
