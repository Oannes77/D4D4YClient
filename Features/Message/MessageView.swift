import SwiftUI

/// 消息：「站内短信」/「系统消息」分段切换（真实 `pm.php`）。
///
/// 数据诚实：论坛页面没给的字段就不显示 —— 没有未读标记就不画红点，
/// 短信一条都没有就提示「还没有站内短信」，解析不出结构就明确说明，
/// 每种失败态都给出「登录 / 重试」出口。
struct MessageView: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var viewModel = MessageViewModel()
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("消息", selection: $viewModel.segment) {
                    ForEach(MessageViewModel.Segment.allCases) { seg in
                        Text(seg.title).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(12)
                .background(Color.appBackground(scheme))

                content
            }
            .background(Color.appBackground(scheme))
            .navigationTitle("消息")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showLogin) { LoginView() }
            .task { await viewModel.load() }
            .onChange(of: viewModel.segment) { _, _ in
                Task { await viewModel.load() }
            }
        }
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载消息…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(Color.appTextSecondary(scheme))

        case .requiresLogin:
            loginPrompt

        case .failed(let message):
            VStack(alignment: .leading) {
                ErrorRow(message: message,
                         debugDetail: "消息页：\(viewModel.segment == .pm ? "pm.php?filter=privatepm" : "pm.php?filter=systempm")") {
                    Task { await viewModel.load() }
                }
                .padding(16)
                Spacer()
            }

        case .loaded(let items) where items.isEmpty:
            emptyState

        case .loaded(let items):
            List {
                ForEach(items) { item in
                    row(for: item)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground(scheme))
            .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private func row(for item: PrivateMessage) -> some View {
        if let uid = item.userID, uid > 0 {
            NavigationLink {
                MessageChatView(userID: uid, userName: item.userName)
            } label: {
                MessageRow(item: item)
            }
        } else {
            // 系统 / 公共消息没有会话对象，只读展示（不跳进一个空会话）。
            MessageRow(item: item)
        }
    }

    private var loginPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.badge")
                .font(.largeTitle)
                .foregroundStyle(Color.appTextTertiary(scheme))
            Text("站内短信需要登录")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary(scheme))
            Text("论坛不允许游客查看短消息。登录 4D4Y 账号后即可查看收件箱与系统消息。")
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
            .accessibilityIdentifier("message-login")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(Color.appTextTertiary(scheme))
            Text(viewModel.segment == .pm ? "还没有站内短信" : "还没有系统消息")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary(scheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 列表行

private struct MessageRow: View {
    let item: PrivateMessage
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(authorID: item.userID, authorName: item.userName, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.userName)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(Color.appTextPrimary(scheme))

                    // 只有页面明确标了「未读」才画红点
                    if item.isUnread == true {
                        Circle()
                            .fill(Color.appPrimary(scheme))
                            .frame(width: 8, height: 8)
                    }

                    Spacer()

                    Text(item.timeRaw)
                        .font(.caption2)
                        .foregroundStyle(Color.appTextTertiary(scheme))
                }

                if !item.subject.isEmpty {
                    Text(item.subject)
                        .font(.caption)
                        .foregroundStyle(Color.appTextPrimary(scheme))
                        .lineLimit(1)
                }

                if !item.preview.isEmpty, item.preview != item.subject {
                    Text(item.preview)
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary(scheme))
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
