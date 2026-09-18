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
                // 顶部稳定锚点：即使首帖尚未完成异步渲染，也能给 ScrollViewReader 一个可靠目标。
                Color.clear.id("detailTop").frame(height: 1)

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
                    // 帖子详情首屏数据量有限，使用 VStack 确保首帖一加载即存在，
                    // 避免 LazyVStack 延迟创建视图导致 scrollTo 首帖失效/截图卡在长帖中间。
                    VStack(spacing: 0) {
                        ForEach(Array(pageData.posts.enumerated()), id: \.element.id) { index, post in
                            if onlyAuthorUID == nil || post.authorID == onlyAuthorUID {
                                PostDetailRow(
                                    post: post,
                                    isOP: index == 0,
                                    onlyAuthorUID: $onlyAuthorUID,
                                    onUser: { uid in selectedUser = uid; showUserCard = true },
                                    onReply: {
                                        withAnimation(nil) { proxy.scrollTo("lastReply", anchor: .bottom) }
                                        showReply = true
                                    },
                                    onQuote: { p in
                                        replyInitial = "引用 \(p.authorName)：\n" + quotePreview(p.htmlContent)
                                        showReply = true
                                    },
                                    onImageTap: { url in presentedImage = FullScreenImage(url: url) }
                                )
                                .id(index == 0 ? "firstPost" : "post-\(post.id)")
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
            .navigationTitle(viewModel.thread.title)
            .navigationBarTitleDisplayMode(.inline)
            // 回复入口固定放在导航栏右上角（永远可见），供截图脚本稳定触发回复 Sheet；
            // 帖子详情操作栏内仍保留回复图标（视觉一致）。
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showReply = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityIdentifier("detail-reply")
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .onChange(of: viewModel.state) { newState in
                // 数据加载完成后，若未要求跳最后回复，则多次滚回首帖顶部。
                // HTMLContentView 的 NSAttributedString 渲染在后台线程完成，完成后会逐步撑开内容高度，
                // 单次 scrollTo 容易错过渲染完成点；这里覆盖从 0.3s 到 4.5s 的时间窗，
                // 只要首帖视图已存在就持续把它置顶，避免截图卡在长帖中间。
                if !jumpToLast, case .loaded = newState {
                    for delay in [0.3, 0.8, 1.3, 1.8, 2.5, 3.5, 4.5] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            withAnimation(nil) { proxy.scrollTo("firstPost", anchor: .top) }
                        }
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
                        withAnimation(nil) { proxy.scrollTo("lastReply", anchor: .bottom) }
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
