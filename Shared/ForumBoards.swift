import Foundation

/// 板块切换 / 板块管理 / 发帖共用的板块描述。
struct BoardChipItem: Identifiable, Hashable {
    let id: Int        // fid
    let name: String
}

/// 内置常用板块（真实 fid）。
///
/// 用途：① 用户尚未配置板块时首页的初始板块；
///      ② 板块管理「可添加板块」与发帖页板块列表在网络不可用时的兜底。
enum ForumBoards {
    static let defaults: [BoardChipItem] = [
        BoardChipItem(id: 2,  name: "Discovery"),
        BoardChipItem(id: 6,  name: "Buy & Sell 交易服务区"),
        BoardChipItem(id: 7,  name: "Geek Talks 奇客怪谈"),
        BoardChipItem(id: 9,  name: "Smartphone"),
        BoardChipItem(id: 12, name: "PalmOS"),
        BoardChipItem(id: 14, name: "Windows Mobile"),
        BoardChipItem(id: 22, name: "麦客爱苹果"),
        BoardChipItem(id: 50, name: "DC,NB,MP3,Gadgets"),
        BoardChipItem(id: 56, name: "iPhone/iPod/iPad"),
        BoardChipItem(id: 60, name: "Android/Chrome/Google"),
    ]

    /// **游客打不开的版块** —— 实测（2026-09-24，桌面 UA、无 Cookie，逐个抓 `forumdisplay.php?fid=N`）：
    ///
    /// | fid | 版块 | 游客结果 |
    /// |---|---|---|
    /// | 2 | Discovery | ❌ 7168 B「您还未登录，无权访问该版块」 |
    /// | 6 | Buy & Sell 交易服务区 | ❌ 7068 B 同上 |
    /// | 7 / 9 / 12 / 14 / 22 / 50 / 56 / 60 | 其余默认版块 | ✅ 78–94 KB 正常页面，有 75 条主题行 |
    ///
    /// 用户 2026-09-24 明确口径：「游客的权限极低，只能浏览除这两个版块之外的其他版块，
    /// 其他任何功能都需要登录。」所以这里是**站点事实**，不是客户端猜测。
    ///
    /// 用途只有两个：① 游客首次进入时**别把他丢到一个打不开的版块**；
    /// ② 胶囊上给个锁标记。**不做本地黑名单** —— 真的点进去拿到的是服务器返回的
    /// 提示页，界面照原文显示 + 给登录入口（见 `SiteAlertParser`）。
    static let loginOnlyFIDs: Set<Int> = [2, 6]

    /// 该版块对游客是否可读。
    static func isLoginOnly(fid: Int) -> Bool { loginOnlyFIDs.contains(fid) }

    /// 给游客挑一个**当前就能读**的版块（列表全被挡时原样返回第一个，不做假动作）。
    static func firstReadableForGuest(in boards: [BoardChipItem]) -> BoardChipItem? {
        boards.first { !isLoginOnly(fid: $0.id) } ?? boards.first
    }
}
