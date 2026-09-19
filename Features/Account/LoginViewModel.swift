import SwiftUI
import Combine

/// 登录流程编排：持有输入状态、驱动 `SessionManager`、并把结果翻译成可展示文案。
///
/// **不持有明文密码以外的任何凭据**；密码仅作为参数传给 `SessionManager`，
/// 由 `LoginRepository` 计算 MD5 后立即丢弃，不落盘、不打印、不进 Keychain。
@MainActor
final class LoginViewModel: ObservableObject {

    @Published var username = ""
    @Published var password = ""
    @Published var questionID: Int = 0
    @Published var answer = ""
    @Published var rememberMe = true
    @Published var errorMessage: String?
    @Published var isBusy = false

    private let session = SessionManager.shared
    private var cancellable: AnyCancellable?

    init() {
        // 会话状态 / 登录表单变化时驱动本 ViewModel 重绘。
        cancellable = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - 派生状态

    /// 安全提问选项：优先用登录页实时解析结果，取不到时用标准兜底列表。
    var questions: [SecurityQuestion] {
        session.loginForm?.questions ?? SecurityQuestion.defaultList
    }

    var isLoadingForm: Bool { session.isLoadingLoginForm }

    var currentQuestion: SecurityQuestion? {
        questions.first { $0.id == questionID }
    }

    /// 当前选中提问是否需要填写答案。
    var needsAnswer: Bool { questionID != 0 }

    // MARK: - 行为

    /// 预取登录页表单（安全提问选项 + formhash）。截图模式下不联网。
    func prepare() async {
        guard !DemoMode.isOn else { return }
        await session.loadLoginForm()
    }

    /// 提交登录。
    /// - Returns: 是否登录成功（供调用方决定是否 dismiss / 切换根视图）。
    func submit() async -> Bool {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else {
            errorMessage = "请输入用户名和密码"
            return false
        }
        if needsAnswer, answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "请填写安全提问答案"
            return false
        }

        isBusy = true
        errorMessage = nil

        await session.login(username: name,
                            password: password,
                            questionID: questionID,
                            answer: answer,
                            rememberMe: rememberMe)

        isBusy = false
        // 清空明文密码，避免长时间驻留内存。
        password = ""

        switch session.state {
        case .authenticated:
            return true
        case .failed(let error):
            errorMessage = error.errorDescription
            return false
        default:
            return false
        }
    }
}
