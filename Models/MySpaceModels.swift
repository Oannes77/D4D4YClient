import Foundation

/// 论坛「我的中心」（`my.php`）里的栏目。
///
/// - `threads` / `replies` / `follows` = 帖子型列表（点击进帖子详情）
///   —— ⚠️「关注」也是帖子型：`attention` 关注的是**主题**，参数是 tid。
/// - `friends` = 用户型列表（点击弹用户卡）
///
/// ⚠️ **item 参数不写死**：真实取值由 `MySpaceRepository` 先从 `my.php` 页内导航
/// **动态发现**，这里只提供兜底候选与「网页版出口」。
/// 站点若改版换名，客户端会跟着走；站点若根本没有这个栏目（`sectionMissing`），
/// 界面会如实说明，而不是假装有一份空列表。
enum MySpaceKind: String, CaseIterable, Identifiable {
    case threads
    case replies
    case friends
    case follows

    var id: String { rawValue }

    /// 宫格 / 入口标题。
    var title: String {
        switch self {
        case .threads: return "帖子"
        case .replies: return "回复"
        case .friends: return "好友"
        case .follows: return "关注"
        }
    }

    /// 列表页导航标题。
    var listTitle: String {
        switch self {
        case .threads: return "我的帖子"
        case .replies: return "我的回复"
        case .friends: return "好友"
        case .follows: return "关注"
        }
    }

    var icon: String {
        switch self {
        case .threads: return "doc.text"
        case .replies: return "bubble.left"
        case .friends: return "person.2"
        case .follows: return "person.crop.circle.badge.checkmark"
        }
    }

    /// 列表里的一行是**用户**（而非帖子）。
    ///
    /// ⚠️ 只有好友是用户型。**「关注」是帖子型** —— Discuz! 的 `my.php?item=attention`
    /// 关注的是**主题**不是人：站点在发帖表单里用 `attention_add=1`（发帖即关注该帖），
    /// 关注 / 取消关注走 `my.php?item=attention&action=add&tid=<tid>`（参数是 **tid**）。
    /// （用户之间的关注是 Discuz X 系列才有的功能，7.2 没有。）
    /// 早期把 follows 归为用户型，会让列表按 `space.php?uid=` 抽取而一条都认不出。
    var isUserList: Bool {
        self == .friends
    }

    /// 该栏目的入口**不在**「我的中心」的页内导航里，而在别的页面。
    ///
    /// 目前只有「关注」如此：站点把 `[关注此主题的新回复]` 放在**帖子页**的 `favoritewin`
    /// 弹层里（`my.php?item=attention&action=add&tid=<tid>`），`my.php` 自身的导航未必有它。
    /// 这类栏目不能凭「导航里没匹配到」就判本站不支持，必须按已知地址试一次。
    /// （2026-09-24 之前把「关注」当成本站没有的栏目，是错的。）
    var hasExternalEntry: Bool {
        self == .follows
    }

    /// 动态发现失败时兜底请求的 item 参数（Discuz 习惯命名）。
    var fallbackItem: String {
        switch self {
        case .threads: return "threads"
        case .replies: return "posts"
        case .friends: return "buddylist"
        case .follows: return "attention"
        }
    }

    /// 在动态发现出的导航里匹配本栏目的 item 候选（按可靠性排序）。
    var itemCandidates: [String] {
        switch self {
        case .threads: return ["threads", "topic", "mythreads"]
        case .replies: return ["posts", "replies", "myposts"]
        case .friends: return ["buddylist", "friends"]
        case .follows: return ["attention", "follow", "follows"]
        }
    }

    /// 导航里没有能识别的 item 时，按**栏目名文本**兜底匹配。
    var labelHints: [String] {
        switch self {
        case .threads: return ["我的话题", "我的主题", "我的帖子"]
        case .replies: return ["我的回复", "回复"]
        case .friends: return ["好友", "我的好友"]
        case .follows: return ["关注", "我的关注"]
        }
    }

    /// 网页版出口（客户端读不出来时给真实可用的去处）。
    var webPath: String { "my.php?item=\(fallbackItem)" }

    /// 在 `menuItems` 结果里定位本栏目的 item 参数。
    /// - Returns: nil 表示导航被成功解析、但**确实没有**这个栏目。
    func resolveItem(in menu: [String: String]) -> String? {
        guard !menu.isEmpty else { return nil }
        for candidate in itemCandidates where menu[candidate] != nil {
            return candidate
        }
        for (item, label) in menu {
            if labelHints.contains(where: { label.contains($0) }) { return item }
        }
        return nil
    }
}

/// 「我的中心」里的一条记录：既可能是帖子（帖子 / 回复），也可能是用户（好友 / 关注）。
struct MySpaceEntry: Identifiable, Hashable {
    let id: String
    let title: String
    /// 次级说明（版块名 / 时间 / 分组等，已剔除标题与时间文本）。
    let detail: String
    let timeRaw: String
    let threadID: Int?
    let userID: Int?
    let userName: String?

    /// 对应的网页版地址：帖子 → 帖子页，用户 → 资料页。
    var webPath: String? {
        if let threadID { return "viewthread.php?tid=\(threadID)" }
        if let userID { return "space.php?uid=\(userID)" }
        return nil
    }
}

/// 列表页的加载状态。
///
/// 刻意区分「空」与「读不出来」：
/// - `.empty`          = 页面正常打开、确实没有内容；
/// - `.requiresLogin`  = 命中登录门（给登录入口）；
/// - `.sectionMissing` = 本站的我的中心里没有这个栏目（明说，不假装空列表）；
/// - `.failed`         = 结构未识别 / 网络失败。
enum MySpaceLoadState {
    case idle
    case loading
    case loaded([MySpaceEntry])
    case empty
    case requiresLogin
    case sectionMissing(String)
    case failed(String)
}
