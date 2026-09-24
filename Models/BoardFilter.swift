import Foundation

/// 板块页排序条上的一个选项（热门 / 一天 / 两天 / 周 / 月 / 季）。
///
/// 设计要点：**全部来自板块页自身的链接**。
/// `path` 就是页面里那个 `<a href="…">` 的**原样相对地址**（只剥掉 `sid`），
/// 我们不自行拼 `orderby=` / `filter=` 参数 —— 站点给什么就用什么，
/// 站点改版或改参数名都不会让客户端失效。
/// 同理，选中态也从页面上读（`li.current` 等），不靠客户端记账。
///
/// ⚠️ 2026-09-24 修订：**主题分类不在这里**。用户明确「标签不用在首页显示，
/// 而是在发帖的时候选」。分类已改为发帖页的下拉（见 `BoardCategory` 与 `NewPostView`）。
struct BoardFilterOption: Identifiable, Hashable {
    /// 相对地址天然唯一（同一页里不会出现两条同址选项）。
    var id: String { path }
    /// 显示文案（页面里的链接文本：热门 / 一天 …）。
    let title: String
    /// 站点原样相对地址，可直接交给 `ForumRepository.threads(pageURL:)` 请求。
    let path: String
    /// 页面是否把这一项标为当前选中。
    let isSelected: Bool
}

/// 板块页的排序条（只含排序 / 时间）。
///
/// 覆盖站点本来就有的能力（真实页面实测）：
/// `orderby=heats`（热门）、`orderby=lastpost&filter=86400`（一天 / 两天 / 周 / 月 / 季）。
///
/// ⚠️ **不做**「精华 / 投票 / 活动」筛选（`filter=digest|poll|activity`）—— 用户明确判定用处不大。
/// 解析时主动跳过这三类链接，避免它们混进条里。
struct BoardFilterBar: Hashable {
    /// 排序与时间范围。
    let sorts: [BoardFilterOption]

    var isEmpty: Bool { sorts.isEmpty }

    /// 当前选中的排序项（没有则 nil）——仅用于日志与调试。
    var selectedSortTitle: String? {
        sorts.first(where: { $0.isSelected })?.title
    }
}

/// 一个板块的**主题分类**（Discuz 的 `typeid`）。
///
/// 为什么它不是「过滤条」而是「发帖选项」：
/// 分类是**发帖时贴给主题的标签**（列表里显示成 `[心得技巧]` 前缀），
/// 每个板块各不相同，站点原文挂在板块页的 `forumdisplay.php?fid=14&filter=type&typeid=10` 这类链接上。
/// 客户端**不硬编码分类表**：发帖时按当前选中的板块去解析一次（游客可见）。
struct BoardCategory: Identifiable, Hashable {
    /// Discuz 的 `typeid`，发帖表单里提交的就是它。
    let id: Int
    /// 分类名（心得技巧 / 求助 / 站务 …）。
    let name: String
}
