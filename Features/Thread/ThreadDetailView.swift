import SwiftUI
import SwiftData

/// 帖子详情（真实数据：viewthread.php?tid=xx）。
///
/// 2026-09-18 Threads 会话视图：
/// - 首帖置顶 + 回复楼层流（ScrollView + ScrollViewReader）。
/// - 每条作者名旁「眼睛」→ 只看该作者（互斥）。
/// - 点「回复」→ 跳最后回复 + 底部回复 Sheet；长按某楼 → 引用并弹回复 Sheet。
/// - 操作栏图标化：回复 / 站内转发 / 收藏 / 报告。
/// - 本地作者屏蔽：命中 `BlockedUser` 时 `PostContent` 显示「该用户内容已隐藏」。
struct ThreadDetailView: View {
    @StateObject private var viewModel: ThreadDetailViewModel
    @StateObject private var replyViewModel: ReplyViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query private var blockedUsers: [BlockedUser]

    @State private var presentedImage: FullScreenImage?
    @State private var onlyAuthorUID: Int?
    @State private var showReply = false
    @State private var replyInitial = "Peace&Love"
    @State private var selectedUser: Int?
    @State private var showUserCard = false
    @State private var jumpToLast = false

    private let forumID: Int?

    init(thread: ForumThread, forumID: Int? = nil, jumpToLastReply: Bool = false) {
        self.forumID = forumID
        self._jumpToLast = State(initialValue: jumpToLastReply)
        _viewModel = StateObject(wrappedValue: ThreadDetailViewModel(thread: thread))
        _replyViewModel = StateObject(wrappedValue: ReplyViewModel(tid: thread.id))
    }

    init(tid: Int, title: String, forumID: Int? = nil) {
        self.forumID = forumID
        _viewModel = StateObject(wrappedValue: ThreadDetailViewModel(thread: ForumThread(
            id: tid, title: title, typeName: nil,
            authorName: "", authorID: nil,
            createdAt: nil, createdAtRaw: "",
            replies: nil, views: nil,
            lastReplyUserName: nil, lastReplyAtRaw: nil)))
        _replyViewModel = StateObject(wrappedValue: ReplyViewModel(tid: tid))
    }

    private var blockedUIDs: Set<Int> {
        Set(blockedUsers.compactMap { $0.uid })
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("加载帖子…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 60)
                        .foregroundStyle(Color.appTextSecondary(scheme))
                case .failed(let message, let detail):
                    ErrorRow(message: message, debugDetail: detail, retry: {
                        Task { await viewModel.load(page: 1) }
                    })
                case .loaded(let pageData):
                    LazyVStack(spacing: 0) {
                        ForEach(pageData.posts) { post in
                            if onlyAuthorUID == nil || post.authorID == onlyAuthorUID {
                                PostDetailRow(
                                    post: post,
                                    isOP: post.id == pageData.posts.first?.id,
                                    onlyAuthorUID: $onlyAuthorUID,
                                    onUser: { uid in selectedUser = uid; showUserCard = true },
                                    onReply: {
                                        withAnimation { proxy.scrollTo("lastReply", anchor: .bottom) }
                                        showReply = true
                                    },
                                    onQuote: { p in
                                        replyInitial = "引用 \(p.authorName)：\n" + quotePreview(p.htmlContent)
                                        showReply = true
                                    },
                                    onImageTap: { url in presentedImage = FullScreenImage(url: url) }
                                )
                                .id("post-\(post.id)")
                                .background(Color.appBackground(scheme))
                                Divider().background(Color.appDivider(scheme))
                            }
                        }
                        Color.clear.id("lastReply")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground(scheme))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: viewModel.state) { newState in
                // 数据加载完成后，若未要求跳到最后回复，则滚回首帖顶部，
                // 避免 ScrollView 内容高度突变后滚动偏移异常（尤其在演示截图时）。
                if !jumpToLast, case .loaded(let page) = newState, let first = page.posts.first {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation { proxy.scrollTo("post-\(first.id)", anchor: .top) }
                    }
                }
            }
            .task {
                if DemoMode.isOn {
                    await viewModel.loadDemo()
                } else {
                    await viewModel.loadFirstPage()
                }
            }
            .onAppear {
                ReadHistory.record(tid: viewModel.thread.id,
                                   title: viewModel.thread.title,
                                   forumID: forumID,
                                   context: modelContext)
                if jumpToLast {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation { proxy.scrollTo("lastReply", anchor: .bottom) }
                    }
                }
            }
            .onDisappear {
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
            .sheet(isPresented: $showReply) {
                ReplySheet(tid: viewModel.thread.id, initial: replyInitial) { _ in }
            }
            .sheet(isPresented: $showUserCard) {
                if let uid = selectedUser { UserCardSheet(userID: uid) }
            }
        }
    }

    /// 把楼层 HTML 正文粗略转纯文本并截断，作为引用预览。
    private func quotePreview(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return String(stripped.prefix(40))
    }
}
