import Foundation
import Combine

/// 消息 Tab 未读角标（真实数量）。
///
/// 只在**真的加载过收件箱并读到未读标记**时才 > 0；没读到未读标记就是 0（角标不显示），
/// 不再像旧版那样写死 `.badge(3)` 假装有 3 条未读。
/// 故意不加 `@MainActor`：它要在 `RootView` 的属性初始化位置被引用（非隔离上下文）。
final class UnreadBadge: ObservableObject {
    static let shared = UnreadBadge()

    @Published private(set) var privateMessages: Int = 0

    private init() {}

    func setPrivateMessages(_ count: Int) {
        privateMessages = max(0, count)
    }
}

/// 消息列表视图模型（站内短信 / 系统消息）。
@MainActor
final class MessageViewModel: ObservableObject {

    enum Segment: String, CaseIterable, Identifiable {
        case pm
        case system

        var id: String { rawValue }
        var title: String { self == .pm ? "站内短信" : "系统消息" }
    }

    enum ListState: Equatable {
        case idle
        case loading
        case loaded([PrivateMessage])
        case requiresLogin
        case failed(String)
    }

    @Published var segment: Segment = .pm
    @Published private(set) var state: ListState = .idle

    private let repository: PMRepositoryProtocol

    init(repository: PMRepositoryProtocol = PMRepository()) {
        self.repository = repository
    }

    func load() async {
        // 演示/截图模式：用离线样例，不联网、不碰鉴权。
        if DemoMode.isOn {
            state = .loaded(segment == .pm ? DemoData.pmInboxDemo() : DemoData.systemMessagesDemo())
            return
        }

        state = .loading
        let result: Result<[PrivateMessage], PMError>
        if segment == .pm {
            result = await repository.inbox()
        } else {
            result = await repository.systemMessages()
        }

        switch result {
        case .success(let items):
            if segment == .pm {
                UnreadBadge.shared.setPrivateMessages(items.filter { $0.isUnread == true }.count)
            }
            state = .loaded(items)
        case .failure(let error):
            Log.network.error("消息列表加载失败: \(String(describing: error), privacy: .public)")
            state = (error == .requiresLogin) ? .requiresLogin : .failed(error.localizedDescription)
        }
    }
}
