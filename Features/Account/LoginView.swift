import SwiftUI

/// 登录页（Sprint 6 最小可用）。
///
/// 仅收集用户名 / 密码并提交给 `SessionManager.login`；明文密码不在此处持久化、不打印。
/// 验证码（seccode）由 `LoginRepository` 在服务端要求时返回 `.captchaRequired` 错误，
/// 本页仅展示提示，**不绕过**。
struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("账户") {
                    TextField("用户名 / UID / Email", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                    SecureField("密码", text: $password)
                        .submitLabel(.go)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.appError(scheme))
                    }
                }

                Section {
                    Button {
                        Task { @MainActor in
                            errorMessage = nil
                            await SessionManager.shared.login(username: username, password: password)
                        }
                    } label: {
                        if SessionManager.shared.state == .authenticating {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("登录")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty ||
                              SessionManager.shared.state == .authenticating)
                }

                Section {
                    Text("登录仅用于浏览会员内容。凭据保存在系统 Keychain，不保存明文密码。")
                        .font(.caption2)
                        .foregroundStyle(Color.appTextTertiary(scheme))
                }
            }
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.appPrimary(scheme))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onReceive(SessionManager.shared.$state) { newState in
                switch newState {
                case .authenticating:
                    errorMessage = nil
                case .authenticated:
                    errorMessage = nil
                    dismiss()
                case .failed(let error):
                    errorMessage = error.errorDescription
                case .guest:
                    break
                }
            }
        }
    }
}
