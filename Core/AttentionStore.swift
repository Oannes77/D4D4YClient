import Foundation
import Combine

/// 关注状态（服务器真源 + 内存缓存）。
///
/// 「关注」在 4D4Y 上是**关注主题的新回复**（`my.php?item=attention`，参数是 tid），
/// 属于论坛服务器数据，登录后才有意义：未登录时由界面引导去登录，不做「本地假装关注」。
///
/// 单例原因与 `FavoritesStore` 相同：详情页与「我的 → 关注」要读同一份状态，
/// 且关注变动后两处应立即一致。
@MainActor
final class AttentionStore: ObservableObject {

    static let shared = AttentionStore()

    /// 当前关注中的 tid 集合（用于详情页按钮状态）。
    @Published private(set) var tids: Set<Int> = []
    /// 关注列表（含标题，供「我的 → 关注」参考）。
    @Published private(set) var items: [AttentionItem] = []
    @Published private(set) var isLoading = false
    /// 最近一次错误（界面如实提示；成功后清空）。
    @Published private(set) var lastError: String?

    private let repository = AttentionRepository()

    private init() {}

    func contains(_ tid: Int) -> Bool { tids.contains(tid) }

    /// 拉取服务器关注列表。Demo 模式用本地样例，不发起网络请求。
    func refresh() async {
        if DemoMode.isOn {
            items = DemoData.attentionDemo()
            tids = Set(items.map(\.tid))
            lastError = nil
            return
        }
        isLoading = true
        defer { isLoading = false }

        switch await repository.list() {
        case .success(let list):
            items = list
            tids = Set(list.map(\.tid))
            lastError = nil
        case .failure(let error):
            // 登录门不当作「错误提示」往外抛：界面按未登录处理即可。
            if error != .notLoggedIn { lastError = error.localizedDescription }
        }
    }

    /// 切换关注状态。
    /// - Returns: 切换后的状态（true = 已关注）；**失败返回 nil**，原因写入 `lastError`。
    @discardableResult
    func toggle(tid: Int) async -> Bool? {
        let shouldInsert = !tids.contains(tid)
        let result = shouldInsert ? await repository.add(tid: tid)
                                  : await repository.remove(tid: tid)
        switch result {
        case .success(let nowAttended):
            if nowAttended { tids.insert(tid) } else { tids.remove(tid) }
            // 用服务器列表回刷一次，保证展示的数据都来自服务器。
            await refresh()
            return nowAttended
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
