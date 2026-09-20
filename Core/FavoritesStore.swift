import Foundation
import Combine

/// 收藏状态（服务器真源 + 内存缓存）。
///
/// 4D4Y 的收藏是**论坛服务器上的收藏**（`my.php?item=favorites&type=thread`），
/// 所以这是登录后才有意义的功能：未登录时由界面引导去登录，不做「本地假装收藏」。
///
/// 单例原因：详情页、首页、搜索结果页、我的中心都要读同一份状态，
/// 且收藏变动后所有入口应立即一致。
@MainActor
final class FavoritesStore: ObservableObject {

    static let shared = FavoritesStore()

    /// 当前收藏的 tid 集合（用于列表 / 详情页的按钮状态）。
    @Published private(set) var tids: Set<Int> = []
    /// 收藏列表（含标题，供「我的 → 收藏」展示）。
    @Published private(set) var items: [FavoriteItem] = []
    @Published private(set) var isLoading = false
    /// 最近一次错误（界面如实提示；成功后清空）。
    @Published private(set) var lastError: String?

    private let repository = FavoriteRepository()

    private init() {}

    func contains(_ tid: Int) -> Bool { tids.contains(tid) }

    /// 拉取服务器收藏列表。Demo 模式用本地样例，不发起网络请求。
    func refresh() async {
        if DemoMode.isOn {
            items = DemoData.favoritesDemo()
            tids = Set(items.map(\.tid))
            lastError = nil
            return
        }
        isLoading = true
        defer { isLoading = false }

        switch await repository.favorites() {
        case .success(let list):
            items = list
            tids = Set(list.map(\.tid))
            lastError = nil
        case .failure(let error):
            // 登录门不当作「错误提示」往外抛：界面按未登录处理即可。
            if error != .notLoggedIn { lastError = error.localizedDescription }
        }
    }

    /// 切换收藏状态。
    /// - Returns: 切换后的状态（true = 已收藏）；**失败返回 nil**，原因写入 `lastError`。
    @discardableResult
    func toggle(tid: Int) async -> Bool? {
        let shouldInsert = !tids.contains(tid)
        let result = shouldInsert ? await repository.add(tid: tid)
                                  : await repository.remove(tid: tid)
        switch result {
        case .success(let nowSaved):
            if nowSaved { tids.insert(tid) } else { tids.remove(tid) }
            // 用服务器列表回刷一次（同时补上标题等信息），保证展示的数据都来自服务器。
            await refresh()
            return nowSaved
        case .failure(let error):
            lastError = error.localizedDescription
            return nil
        }
    }

    /// 清空内存状态（退出登录时调用）。
    func clear() {
        tids = []
        items = []
        lastError = nil
    }
}
