import Foundation
import SwiftUI

/// 回复编辑器对应的 ViewModel。
///
/// 职责边界：
/// - 持有输入文本、提交中状态、错误提示。
/// - 通过 `ReplyRepository` 提交回复；不直接触碰 Cookie / formhash / POST 参数 / GBK 编码。
/// - 提交成功后通过 `onSuccess` 回调通知上层刷新帖子。
@MainActor
final class ReplyViewModel: ObservableObject {
    @Published var message = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?

    private let tid: Int
    private let repository: ReplyRepository

    init(tid: Int, repository: ReplyRepository = ReplyRepository()) {
        self.tid = tid
        self.repository = repository
    }

    /// 提交回复。
    /// - Parameter onSuccess: 提交成功后由上层执行刷新逻辑（如回到末页重新加载）。
    func submit(onSuccess: @escaping () -> Void) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "请输入回复内容"
            return
        }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }

        let result = await repository.submitReply(tid: "\(tid)", message: trimmed)
        switch result {
        case .success:
            message = ""
            successMessage = "回复成功"
            onSuccess()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// 供 UI 在输入变化时主动清空错误/成功提示。
    func clearFeedback() {
        errorMessage = nil
        successMessage = nil
    }
}
