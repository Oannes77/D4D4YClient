import Foundation
import Combine

/// 私信会话视图模型（`pm.php?action=view&uid=NNN`）。
@MainActor
final class MessageChatViewModel: ObservableObject {

    enum ChatState: Equatable {
        case idle
        case loading
        case loaded([PMBubble])
        case requiresLogin
        case failed(String)
    }

    @Published private(set) var state: ChatState = .idle
    /// 发送提示（成功 / 失败原因）。
    @Published var notice: String?
    /// 是否正在发送（禁用按钮，避免重复提交）。
    @Published private(set) var isSending = false

    private let repository: PMRepositoryProtocol
    private let userID: Int?
    private let userName: String

    init(userID: Int?,
         userName: String,
         repository: PMRepositoryProtocol = PMRepository()) {
        self.userID = userID
        self.userName = userName
        self.repository = repository
    }

    func load(myUserID: Int?) async {
        if DemoMode.isOn {
            state = .loaded(DemoData.pmConversationDemo())
            return
        }
        guard let userID, userID > 0 else {
            state = .failed("这条短信没有对应的用户 UID，无法打开会话。")
            return
        }

        state = .loading
        switch await repository.conversation(uid: userID, userName: userName, myUserID: myUserID) {
        case .success(let conversation):
            state = .loaded(conversation.bubbles)
        case .failure(let error):
            Log.network.error("私信会话加载失败: \(String(describing: error), privacy: .public)")
            state = (error == .requiresLogin) ? .requiresLogin : .failed(error.localizedDescription)
        }
    }

    /// 发送私信：走真实 `pm.php`（运行时动态解析发送表单 + GBK 提交 + 回会话页确认）。
    /// 只有服务端确认后才返回 true（调用方据此清空输入框）；失败**保留输入内容**并说明原因，
    /// 绝不出现「清空输入框假装已发送」。
    @discardableResult
    func send(_ text: String, myUserID: Int?) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // 演示/截图模式：不联网、不碰鉴权，也不假装成功。
        if DemoMode.isOn {
            notice = "演示模式：不会真的发送短信。"
            return false
        }
        guard let userID, userID > 0 else {
            notice = "这条短信没有对应的用户 UID，无法发送。"
            return false
        }

        isSending = true
        defer { isSending = false }

        switch await repository.send(uid: userID, message: trimmed) {
        case .success:
            await load(myUserID: myUserID)
            notice = "发送成功"
            return true
        case .failure(let error):
            Log.network.error("私信发送失败: \(String(describing: error), privacy: .public)")
            state = (error == .requiresLogin) ? .requiresLogin : state
            notice = error.localizedDescription
            return false
        }
    }
}
