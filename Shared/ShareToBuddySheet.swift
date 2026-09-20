import SwiftUI

/// 「分享给好友」。
///
/// 论坛的站内分享只能发给好友，所以这里：读真实好友列表（`my.php?item=buddylist`）
/// → 选一位 → 用 `PMRepository` 发一条附帖子链接的私信。
///
/// 失败一律如实呈现：未登录给登录入口；没有好友就说没有；发送结果以回读为准，
/// **绝不假装「已分享」**。
struct ShareToBuddySheet: View {

    /// 要分享的帖子网页地址。
    let threadURL: URL
    /// 帖子标题（私信正文第一行）。
    let threadTitle: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private let buddyRepository = BuddyRepository()
    private let pmRepository = PMRepository()

    enum LoadState: Equatable {
        case loading
        case loaded([BuddyEntry])
        case empty
        case requiresLogin
        case failed(String)
    }

    @State private var state: LoadState = .loading
    @State private var sendingUID: Int?
    @State private var notice: String?
    @State private var didSend = false
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("分享给好友")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
                .task { await load() }
                .sheet(isPresented: $showLogin) { LoginView() }
                .alert("提示", isPresented: Binding(
                    get: { notice != nil },
                    set: { if !$0 { notice = nil } }
                )) {
                    Button("好", role: .cancel) {
                        let sent = didSend
                        notice = nil
                        if sent { dismiss() }
                    }
                } message: {
                    Text(notice ?? "")
                }
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("正在读取好友列表…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(Color.appTextSecondary(scheme))

        case .loaded(let buddies):
            List(buddies) { buddy in
                Button {
                    Task { await send(to: buddy) }
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(authorID: buddy.uid, authorName: buddy.name, size: 36)
                        Text(buddy.name)
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextPrimary(scheme))
                        Spacer()
                        if sendingUID == buddy.uid {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane")
                                .foregroundStyle(Color.appPrimary(scheme))
                        }
                    }
                }
                .disabled(sendingUID != nil)
                .listRowBackground(Color.appBackground(scheme))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

        case .empty:
            placeholder(
                icon: "person.2",
                title: "还没有好友",
                detail: "论坛的站内分享只能发给好友。可以先用帖子里的「分享」复制链接，或用系统分享发出去。"
            )

        case .requiresLogin:
            placeholder(
                icon: "person.crop.circle.badge.exclamationmark",
                title: "需要登录",
                detail: "好友列表需要登录后才能读取。",
                actionTitle: "去登录"
            ) { showLogin = true }

        case .failed(let message):
            placeholder(icon: "exclamationmark.triangle", title: "读不出好友列表", detail: message)
        }
    }

    private func placeholder(icon: String, title: String, detail: String,
                             actionTitle: String? = nil,
                             action: (() -> Void)? = nil) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(Color.appTextTertiary(scheme))
            Text(title)
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(Color.appTextPrimary(scheme))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Color.appTextSecondary(scheme))
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline)
                    .foregroundStyle(Color.appPrimary(scheme))
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 数据

    private func load() async {
        switch await buddyRepository.buddies() {
        case .success(let buddies):
            state = buddies.isEmpty ? .empty : .loaded(buddies)
        case .failure(let error):
            state = (error == .notLoggedIn) ? .requiresLogin : .failed(error.localizedDescription)
        }
    }

    /// 发送私信（标题 + 链接），结果以 `PMRepository` 的确认结果为准。
    private func send(to buddy: BuddyEntry) async {
        guard sendingUID == nil else { return }
        sendingUID = buddy.uid
        let body = "\(threadTitle)\n\(threadURL.absoluteString)"
        switch await pmRepository.send(uid: buddy.uid, message: body) {
        case .success:
            didSend = true
            notice = "已通过站内短信发送给 \(buddy.name)。"
        case .failure(let error):
            notice = error.localizedDescription
        }
        sendingUID = nil
    }
}
