import Foundation

/// 板块页顶部筛选条上的一个选项（主题分类 / 排序 / 时间范围）。
///
/// 设计要点：**全部来自板块页自身的链接**。
/// `path` 就是页面里那个 `<a href="…">` 的**原样相对地址**（只剥掉 `sid`），
/// 我们不自行拼 `filter=` / `orderby=` 参数 —— 站点给什么就用什么，
/// 站点改版或改参数名都不会让客户端失效。
/// 同理，选中态也从页面上读（`li.current` 等），不靠客户端记账。
struct BoardFilterOption: Identifiable, Hashable {
    /// 相对地址天然唯一（同一页里不会出现两条同址选项）。
    var id: String { path }
    /// 显示文案（页面里的链接文本：心得技巧 / 热门 / 一天 …）。
    let title: String
    /// 站点原样相对地址，可直接交给 `ForumRepository.threads(pageURL:)` 请求。
    let path: String
    /// 页面是否把这一项标为当前选中。
    let isSelected: Bool
}

/// 板块页顶部筛选条：**分类在前**，排序与时间在后。
///
/// 覆盖的是站点本来就有的能力（真实页面实测）：
/// - 分类：`forumdisplay.php?fid=14&filter=type&typeid=10`（心得技巧 / 求助 / 站务 …，每个板块不同）
/// - 排序时间：`orderby=heats`（热门）、`orderby=lastpost&filter=86400`（一天 / 两天 / 周 / 月 / 季）
///
/// ⚠️ **不做**「精华 / 投票 / 活动」筛选（`filter=digest|poll|activity`）—— 用户明确判定用处不大。
/// 解析时主动跳过这三类链接，避免它们混进条里。
struct BoardFilterBar: Hashable {
    /// 主题分类。首项固定是「全部」（页面工具栏里的复位链接）。
    let categories: [BoardFilterOption]
    /// 排序与时间范围。
    let sorts: [BoardFilterOption]

    var isEmpty: Bool { categories.isEmpty && sorts.isEmpty }

    /// 当前选中的分类名（没有则 nil）——仅用于日志与调试。
    var selectedCategoryTitle: String? {
        categories.first(where: { $0.isSelected })?.title
    }
}
