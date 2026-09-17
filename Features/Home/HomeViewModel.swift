import Foundation

/// 首页本地聚合辅助。
/// 首页数据来自 SwiftData @Query（见 HomeView），本类只做纯计算，不持有上下文，
/// 保持 MVVM 分层习惯，同时不引入网络依赖。
@MainActor
final class HomeViewModel: ObservableObject {
    /// 限制最近浏览展示数量，避免首页过长。
    func limitedHistory(_ history: [ReadHistory], max: Int = 20) -> [ReadHistory] {
        Array(history.prefix(max))
    }
}
