import SwiftUI
import SwiftData

/// 我的收藏（**论坛服务器上的收藏**：`my.php?item=favorites&type=thread`）。
///
/// 收藏是服务器数据，所以**需要登录**：未登录时给登录入口，不用本地列表假装。
/// 三种状态严格区分：真的没有收藏 / 需要登录 / 读不出来（结构变化或网络问题）。
struct SavedThreadsView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var favorites = FavoritesStore.shared

    @State private var isLoggedIn = SessionManager.shared.state.isAuthenticated
    @State private var showLogin = false
    @State private var loadError: String?

    var body: some View {
        Group {
            if !isLoggedIn && !DemoMode.isOn {
                loginPrompt
            } else if favorites.items.isEmpty, let loadError {
                messageState(icon: "exclamationmark.triangle",
                             title: "读不出收藏列表", detail: loadError)
            } else if favorites.items.isEmpty {
                messageState(icon: "star",
                             title: "还没有收藏的帖子",
                             detail: "在帖子详情页点 ☆ 即可收藏，收藏会同步到你的 4D4Y 账号。")
            } else {
                list
            }
        }
        .background(Color.appBackground(scheme))
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            isLoggedIn = DemoMode.isOn || SessionManager.shared.state.isAuthenticated
            await favorites.refresh()
            loadError = favorites.lastError
        }
        .refreshable {
            await favorites.refresh()
            loadError = favorites.lastError
        }
        .sheet(isPresented: $showLogin) { LoginView() }
    }

    // MARK: - 列表

    private var list: some View {
        List {
            ForEach(favorites.items) { item in
                NavigationLink {
                    ThreadDetailView(tid: item.tid, title: item.title)
                } label: {
                    row(item)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task {
                            await favorites.toggle(tid: item.tid)
                            loadError = favorites.lastError
                        }
                    } label: {
                        Label("取消收藏", systemImage: "star.slash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ item: FavoriteItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(Color.appTextPrimary(scheme))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                if !item.detail.isEmpty {
                    Text(item.detail)
                }
                Spacer()
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.appGold(scheme))
            }
            .font(.caption2)
            .foregroundStyle(Color.appTextTertiary(scheme))
        }
        .padding(.vertical, 4)
    }

    // MARK: - 状态

    private var loginPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(Color.appTextTertiary(scheme))
            Text("收藏需要登录")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary(scheme))
            Text("登录后这里会显示你 4D4Y 账号里的收藏帖子。")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.appTextTertiary(scheme))
            Button("去登录") { showLogin = true }
                .font(.subheadline)
                .foregroundStyle(Color.appPrimary(scheme))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(Color.appTextTertiary(scheme))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary(scheme))
            Text(detail)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.appTextTertiary(scheme))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 黑名单（本地屏蔽的作者）。
///
/// 只影响本机阅读（列表与楼层隐藏该作者内容），不修改任何服务器数据。
struct BlockedUsersView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \BlockedUser.createdAt, order: .reverse) private var blocked: [BlockedUser]

    var body: some View {
        Group {
            if blocked.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(blocked) { user in
                        row(user)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    BlockedUser.unblock(uid: user.uid, context: context)
                                } label: {
                                    Label("取消屏蔽", systemImage: "eye")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.appBackground(scheme))
        .navigationTitle("黑名单")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func row(_ user: BlockedUser) -> some View {
        HStack(spacing: 12) {
            AvatarView(authorID: user.uid, authorName: user.username, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(user.username)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(Color.appTextPrimary(scheme))
                Text("UID \(user.uid) · 已在本机隐藏其内容")
                    .font(.caption2)
                    .foregroundStyle(Color.appTextTertiary(scheme))
            }

            Spacer()

            Button {
                BlockedUser.unblock(uid: user.uid, context: context)
            } label: {
                Text("取消屏蔽")
                    .font(.caption)
                    .foregroundStyle(Color.appPrimary(scheme))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.largeTitle)
                .foregroundStyle(Color.appTextTertiary(scheme))
            Text("黑名单是空的")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary(scheme))
            Text("在帖子列表或楼层里长按作者，即可加入黑名单（仅本机生效）")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.appTextTertiary(scheme))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
