import SwiftUI

/// 登录表单主体（Threads 风格，无导航容器，便于 sheet / 全屏两种场景复用）。
///
/// 字段：用户名 → 密码 → 安全提问（选了提问才出现答案框）→ 记住登录 → 登录按钮。
/// 明文密码只在 `LoginViewModel` 内存中存在，提交后立即清空，不持久化。
struct LoginFormView: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var viewModel = LoginViewModel()

    /// 登录成功回调（全屏门禁场景可留空：根视图会随会话状态自动切换）。
    var onSuccess: () -> Void = {}

    var body: some View {
        VStack(spacing: 24) {
            brandHeader
            inputCard
            rememberToggle
            errorMessageView
            loginButton
            footnote
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 24)
        .task { await viewModel.prepare() }
    }

    // MARK: - 品牌头

    private var brandHeader: some View {
        VStack(spacing: 8) {
            Text("4D4Y")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Color.appPrimary(scheme))

            Text("登录后可浏览 Discovery 与交易服务区")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary(scheme))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - 输入卡片

    private var inputCard: some View {
        VStack(spacing: 0) {
            inputRow(icon: "person") {
                TextField("用户名", text: $viewModel.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .submitLabel(.next)
                    .foregroundStyle(Color.appTextPrimary(scheme))
            }

            divider

            inputRow(icon: "lock") {
                SecureField("密码", text: $viewModel.password)
                    .textFieldStyle(.plain)
                    .submitLabel(.go)
                    .foregroundStyle(Color.appTextPrimary(scheme))
                    .onSubmit { Task { await handleSubmit() } }
            }

            divider

            inputRow(icon: "questionmark.circle") {
                Picker("安全提问", selection: $viewModel.questionID) {
                    ForEach(viewModel.questions) { q in
                        Text(q.text).tag(q.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.appTextPrimary(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.needsAnswer {
                divider
                inputRow(icon: "pencil") {
                    TextField("安全提问答案", text: $viewModel.answer)
                        .textFieldStyle(.plain)
                        .submitLabel(.go)
                        .foregroundStyle(Color.appTextPrimary(scheme))
                        .onSubmit { Task { await handleSubmit() } }
                }
            }
        }
        .background(Color.appSurface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appDivider(scheme), lineWidth: 0.5)
        )
    }

    private var divider: some View {
        Divider()
            .padding(.leading, 52)
            .background(Color.appDivider(scheme))
    }

    private func inputRow<Content: View>(
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.appPrimary(scheme))
                .frame(width: 24, alignment: .center)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - 记住登录

    private var rememberToggle: some View {
        Toggle(isOn: $viewModel.rememberMe) {
            Text("记住登录状态（30 天）")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary(scheme))
        }
        .tint(Color.appPrimary(scheme))
        .padding(.horizontal, 4)
    }

    // MARK: - 错误提示

    @ViewBuilder
    private var errorMessageView: some View {
        if let message = viewModel.errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                Text(message)
            }
            .font(.footnote)
            .foregroundStyle(Color.appError(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - 登录按钮

    private var loginButton: some View {
        Button {
            Task { await handleSubmit() }
        } label: {
            ZStack {
                if viewModel.isBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("登录")
                        .font(.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .background(viewModel.isBusy ? Color.appPrimaryPressed(scheme) : Color.appPrimary(scheme))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 25))
        .disabled(viewModel.isBusy)
        .accessibilityIdentifier("login-submit")
    }

    private var footnote: some View {
        Text("凭据仅保存在系统钥匙串（Keychain），本应用不保存明文密码。")
            .font(.caption2)
            .foregroundStyle(Color.appTextTertiary(scheme))
            .multilineTextAlignment(.center)
    }

    private func handleSubmit() async {
        let ok = await viewModel.submit()
        if ok { onSuccess() }
    }
}

// MARK: - Sheet 形态登录页

/// 以 sheet 弹出的登录页（「我的 → 账号与安全 / 点击登录」场景）。
struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                LoginFormView { dismiss() }
            }
            .background(Color.appBackground(scheme))
            .scrollContentBackground(.hidden)
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .tint(Color.appPrimary(scheme))
    }
}

// MARK: - 全屏门禁

/// 未登录时的全屏门禁页：登录表单 + "先以游客身份浏览"次要出口。
///
/// 之所以提供游客出口：技术版区对游客开放，直接锁死会把可浏览内容也挡掉。
struct LoginGateView: View {
    @Environment(\.colorScheme) private var scheme

    /// 用户选择以游客身份继续（进入 Tab，但 Discovery / 交易区仍不可见）。
    var onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LoginFormView()

                Button {
                    onSkip()
                } label: {
                    Text("先以游客身份浏览")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary(scheme))
                }
                .accessibilityIdentifier("login-skip")

                Text("游客仅可浏览公开技术版区，Discovery 与交易服务区需登录后可见。")
                    .font(.caption2)
                    .foregroundStyle(Color.appTextTertiary(scheme))
                    .multilineTextAlignment(.center)
            }
        }
        .background(Color.appBackground(scheme))
        .scrollContentBackground(.hidden)
        // 截图模式：跟随 -DarkMode 参数输出深色版本；正常构建为 nil（跟随系统）。
        .preferredColorScheme(DemoMode.isDark ? .dark : nil)
    }
}
