import Foundation

/// 已登录会话的本地表示（纯数据容器）。
///
/// 当前阶段**不构造任何实例**；仅作为后续登录阶段的数据载体预留。
/// 这里不包含任何凭证获取、Cookie 管理或网络请求逻辑。
struct UserSession: Identifiable, Equatable {
    /// 用户唯一 ID（来自论坛 UID）。
    let uid: Int
    /// 用户名快照（展示用，真实值以服务器为准）。
    var username: String
    /// 登录时间（本地记录）。
    var loginTime: Date

    var id: Int { uid }
}
