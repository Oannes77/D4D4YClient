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
    /// 发送提示（发送接口本轮未接入时明确告知，不假装发送成功）。
    @Published var notice: String?

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

    /// 发送私信：论坛提交参数（formhash / pmsubmit）需登录态才能验证，
    /// 本轮不接，明确提示而不是清空输入框假装已发送。
    func sendUnavailable() {
        notice = "发送私信尚未接入：需要登录态验证论坛提交参数，下一轮补上。"
    }
}
