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
}
