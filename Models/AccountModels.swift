import Foundation

// MARK: - 站内短信（Discuz! pm.php）
//
// 诚实原则（与 Sprint 10 一致）：论坛页面没有输出的字段一律为可选，
// 界面按字段存在性渲染，**不伪造数字、不伪造已读状态**。

/// 短消息列表中的一条（收件箱 / 系统消息）。
///
/// 数据来源：`pm.php`（**需登录**，游客返回登录门）。
/// 页面只保证给出「谁 / 什么时候 / 说了什么」，其余字段解析不到即为 nil。
struct PrivateMessage: Identifiable, Hashable {
    /// 稳定唯一标识：优先 pmid，其次 uid，最后回退到内容指纹（同一份 HTML 反复解析结果一致）。
    let id: String
    /// 单条短消息的 pmid；列表页未给出时为 nil。
    let pmid: Int?
    /// 会话对方的 uid（会话页锚点）；系统 / 公共消息为 nil。
    let userID: Int?
    /// 对方用户名（系统消息为「系统消息」）。
    let userName: String
    /// 标题。该模板不输出标题时回退为正文首行（截断），不编造。
    let subject: String
    /// 正文摘要（单行，截断）。
    let preview: String
    /// 页面上的时间原文（如「2004-11-3 22:22」/「昨天 21:04」）。
    let timeRaw: String
    /// 未读标记。页面没有任何未读标识时为 nil —— 不用「已读」冒充未知。
    let isUnread: Bool?
}

/// 私信会话中的一条气泡。
struct PMBubble: Identifiable, Hashable {
    let id: String
    let text: String
    let timeRaw: String
    /// 是否为自己发出（依据楼层内的 space.php?uid= 与当前登录 uid 比对）。
    let isMe: Bool
    /// 发言者名（比对不出时为 nil，界面只按左右分侧）。
    let senderName: String?
}

/// 一次私信往来（与某个用户）。
struct PMConversation: Hashable {
    let userID: Int?
    let userName: String
    let bubbles: [PMBubble]
}

// MARK: - 会员资料（space.php）

/// 会员资料卡数据。
///
/// 数据来源：`space.php?uid=NNN`（**需登录**）。
/// 所有字段可空：解析不到的字段界面直接隐藏，绝不填示例数字。
struct UserProfile: Hashable {
    let uid: Int
    let name: String
    let group: String?
    let posts: Int?
    let points: Int?
    let signature: String?
    let registeredRaw: String?
    let location: String?
}
