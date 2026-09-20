import SwiftUI

/// 私信会话（消息 → 站内短信 → 选一条短信）。
///
/// Threads 极简气泡：对方消息靠左灰底，自己的消息靠右紫色；底部输入框常驻。
/// 数据来自真实 `pm.php?action=view&uid=NNN`；未登录时给登录入口，
/// 发送接口未接入前**不假装发送成功**（明确提示，输入内容保留）。
struct MessageChatView: View {
    let userID: Int?
    let userName: String

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: SessionManager
    @StateObject private var viewModel: MessageChatViewModel
    /// 私信不使用占位符：输入框初始为空，仅保留系统提示「发消息…」。
    @State private var draft = ""
    @State private var showLogin = false

    init(userID: Int? = nil, userName: String) {
        self.userID = userID
        self.userName = userName
        _viewModel = StateObject(wrappedValue: MessageChatViewModel(userID: userID, userName: userName))
    }

    private var myUserID: Int? {
        if case .authenticated(let user) = session.state { return user.uid }
        return nil
    }

    private var canCompose: Bool {
        DemoMode.isOn || session.state.isAuthenticated
    }

    private var showNotice: Binding<Bool> {
        Binding(get: { viewModel.notice != nil },
                set: { if !$0 { viewModel.notice = nil } })
    }

    var body: some View {
        VStack(spacing: 0) {
            content

            if canCompose {
                Divider().background(Color.appDivider(scheme))
                composer
            }
        }
        .background(Color.appBackground(scheme))
        .navigationTitle(userName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(myUserID: myUserID) }
        .sheet(isPresented: $showLogin) { LoginView() }
        .alert("发送私信", isPresented: showNotice) {
            Button("好", role: .cancel) { viewModel.notice = nil }
        } message: {
            Text(viewModel.notice ?? "")
        }
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载私信…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(Color.appTextSecondary(scheme))

        case .requiresLogin:
            loginPrompt

        case .failed(let message):
            VStack(alignment: .leading) {
                ErrorRow(message: message,
                         debugDetail: "pm.php?action=view&uid=\(userID.map(String.init) ?? "-")") {
                    Task { await viewModel.load(myUserID: myUserID) }
                }
                .padding(16)
                Spacer()
            }

        case .loaded(let bubbles) where bubbles.isEmpty:
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.largeTitle)
                    .foregroundStyle(Color.appTextTertiary(scheme))
                Text("与 \(userName) 还没有往来短信")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary(scheme))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let bubbles):
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(bubbles) { bubble in
                        bubbleView(bubble)
                    }
                }
                .padding(16)
            }
            .defaultScrollAnchor(.bottom)
            .scrollContentBackground(.hidden)
            .refreshable { await viewModel.load(myUserID: myUserID) }
        }
    }

    private var loginPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.badge")
                .font(.largeTitle)
                .foregroundStyle(Color.appTextTertiary(scheme))
            Text("私信需要登录")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary(scheme))
            Text("登录 4D4Y 账号后可查看与 \(userName) 的往来短信。")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.appTextSecondary(scheme))
            Button {
                showLogin = true
            } label: {
                Text("登录")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appPrimary(scheme))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.top, 4)
            .accessibilityIdentifier("chat-login")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 气泡

    private func bubbleView(_ bubble: PMBubble) -> some View {
        HStack {
            if bubble.isMe { Spacer(minLength: 48) }

            VStack(alignment: bubble.isMe ? .trailing : .leading, spacing: 4) {
                Text(bubble.text)
                    .font(.subheadline)
                    .foregroundStyle(bubble.isMe ? .white : Color.appTextPrimary(scheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        bubble.isMe
                            ? Color.appPrimary(scheme)
                            : Color.appSurfaceSecondary(scheme)
                    )
                    .cornerRadius(16)
                    .textSelection(.enabled)

                Text(bubble.timeRaw)
                    .font(.caption2)
                    .foregroundStyle(Color.appTextTertiary(scheme))
            }

            if !bubble.isMe { Spacer(minLength: 48) }
        }
    }

    // MARK: - 输入区

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("发消息…", text: $draft, axis: .vertical)
                .padding(10)
                .background(Color.appSurfaceSecondary(scheme))
                .cornerRadius(18)
                .foregroundStyle(Color.appTextPrimary(scheme))

            Button("发送") {
                viewModel.sendUnavailable()
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(draft.isEmpty ? Color.appTextTertiary(scheme) : Color.appPrimary(scheme))
            .disabled(draft.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.appBackground(scheme))
    }
}
