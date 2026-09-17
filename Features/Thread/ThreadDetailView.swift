import SwiftUI
import SwiftData

/// 帖子详情（真实数据：viewthread.php?tid=xx）。
///
/// Sprint 7D 调整：
/// - 底部融合 `ReplyEditor`：登录用户可输入回复，游客显示登录提示。
/// - 回复成功后自动跳到帖子末页刷新，确认新楼层出现。
/// - 楼层阅读布局：`PostCell`（头部 头像/用户名/时间/楼层 + 分隔线 + 正文/图片）。
/// - 本地作者屏蔽：`@Query` 读取 `BlockedUser`，命中则 `PostCell` 显示「该用户内容已隐藏」。
/// - 图片体验：`PostContent` 提取 `<img>` 以缩略图呈现，点击经 `fullScreenCover` 调起 `ImageViewer` 全屏缩放。
/// - 阅读历史：`onAppear` 记录进入；`onDisappear` 写入当前页最后楼层 pid，支撑未来「继续阅读」。
struct ThreadDetailView: View {
    @StateObject private var viewModel: ThreadDetailViewModel
    @StateObject private var replyViewModel: ReplyViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query private var blockedUsers: [BlockedUser]
    @State private var presentedImage: FullScreenImage?

    /// 所属版块 ID（来自列表上下文），用于 ReadHistory.forumID；未知时为 nil。
    private let forumID: Int?

    init(thread: ForumThread, forumID: Int? = nil) {
        self.forumID = forumID
        _viewModel = StateObject(wrappedValue: ThreadDetailViewModel(thread: thread))
        _replyViewModel = StateObject(wrappedValue: ReplyViewModel(tid: thread.id))
    }

    /// 仅已知 tid / 标题时（如首页最近浏览）进入详情。
    /// ThreadDetailViewModel 仅依赖 thread.tid 加载，其余字段给合理默认值即可。
    init(tid: Int, title: String, forumID: Int? = nil) {
        self.forumID = forumID
        let thread = ForumThread(
            id: tid, title: title, typeName: nil,
            authorName: "", authorID: nil,
            createdAt: nil, createdAtRaw: "",
            replies: nil, views: nil,
            lastReplyUserName: nil, lastReplyAtRaw: nil)
        _viewModel = StateObject(wrappedValue: ThreadDetailViewModel(thread: thread))
        _replyViewModel = StateObject(wrappedValue: ReplyViewModel(tid: tid))
    }

    /// 本地已屏蔽作者 uid 集合（用于逐楼层判定）。
    private var blockedUIDs: Set<Int> {
        Set(blockedUsers.compactMap { $0.uid })
    }

    var body: some View {
        List {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("加载帖子…")
                    .frame(maxWidth: .infinity, alignment: .center)
            case .failed(let message, let detail):
                ErrorRow(message: message, debugDetail: detail, retry: {
                    Task { await viewModel.load(page: 1) }
                })
            case .loaded(let pageData):
                Text(pageData.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appTextPrimary(scheme))
                    .listRowBackground(Color.appBackground(scheme))

                ForEach(pageData.posts) { post in
                    PostCell(
                        post: post,
                        isBlocked: post.authorID.map { blockedUIDs.contains($0) } ?? false,
                        onImageTap: { url in presentedImage = FullScreenImage(url: url) }
                    )
                    .listRowBackground(Color.appBackground(scheme))
                }

                paginationFooter(pageInfo: pageData.pageInfo)
                    .listRowBackground(Color.appBackground(scheme))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground(scheme))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadFirstPage() }
        .onAppear {
            ReadHistory.record(tid: viewModel.thread.id,
                               title: viewModel.thread.title,
                               forumID: forumID,
                               context: modelContext)
        }
        .onDisappear {
            // 写入当前页最后浏览到的楼层 pid，支撑未来「继续阅读」。
            if case .loaded(let page) = viewModel.state,
               let lastPost = page.posts.last {
                ReadHistory.record(tid: viewModel.thread.id,
                                   title: viewModel.thread.title,
                                   forumID: forumID,
                                   lastReadPostID: lastPost.id,
                                   context: modelContext)
            }
        }
        .fullScreenCover(item: $presentedImage) { item in
            ImageViewer(url: item.url)
        }
        .safeAreaInset(edge: .bottom) {
            ReplyEditor(viewModel: replyViewModel) {
                Task { await viewModel.refreshToLastPage() }
            }
        }
    }

    @ViewBuilder
    private func paginationFooter(pageInfo: PageInfo) -> some View {
        HStack {
            Button("上一页") { Task { await viewModel.goToPreviousPage() } }
                .disabled(pageInfo.previousPageURL == nil)
            Spacer()
            Text("第 \(pageInfo.currentPage) / \(pageInfo.totalPages) 页")
                .font(.footnote)
                .foregroundStyle(Color.appTextSecondary(scheme))
            Spacer()
            Button("下一页") { Task { await viewModel.goToNextPage() } }
                .disabled(pageInfo.nextPageURL == nil)
        }
        .buttonStyle(.bordered)
    }
}
