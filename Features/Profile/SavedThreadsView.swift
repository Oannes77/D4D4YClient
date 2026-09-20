import SwiftUI
import SwiftData

/// 我的收藏（本地书签）。
///
/// 数据源是本地 `SavedThread`：用户在**帖子详情点 ☆** 时写入。
/// 说明：4D4Y 的 Discuz 模板已把帖子页的收藏入口整块注释掉，服务端收藏接口无法验证，
/// 因此客户端不做「假装收藏到论坛」，收藏一律为**本地书签**（只写本机 SwiftData）。
/// 这里展示的只可能是用户自己在本机收藏过的帖子，绝不编造内容。
struct SavedThreadsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \SavedThread.savedAt, order: .reverse) private var saved: [SavedThread]

    var body: some View {
        Group {
            if saved.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(saved) { item in
                        NavigationLink {
                            ThreadDetailView(tid: item.tid, title: item.title)
                        } label: {
                            row(item)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.appBackground(scheme))
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - 行

    private func row(_ item: SavedThread) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(Color.appTextPrimary(scheme))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                if let board = item.boardName, !board.isEmpty {
                    Text(board)
                }
                if let author = item.authorName, !author.isEmpty {
                    Text(author)
                }
                Text(item.savedAt.formatted(date: .numeric, time: .shortened))
                Spacer()
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.appGold(scheme))
            }
            .font(.caption2)
            .foregroundStyle(Color.appTextTertiary(scheme))
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "star")
                .font(.largeTitle)
                .foregroundStyle(Color.appTextTertiary(scheme))
            Text("还没有收藏的帖子")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary(scheme))
            Text("在帖子详情页点 ☆ 即可收藏到这里（收藏只保存在本机）")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.appTextTertiary(scheme))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 删除

    private func delete(at offsets: IndexSet) {
        for index in offsets where saved.indices.contains(index) {
            SavedThread.remove(tid: saved[index].tid, context: context)
        }
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
