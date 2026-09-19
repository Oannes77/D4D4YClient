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
        // Demo/截图模式：不用 ScrollView，避免 UIKit UITextView 内容高度变化导致
        // SwiftUI ScrollView 滚动位置漂移，保证截图首帖（头像/作者/眼睛/操作栏）
        // 一定可见。正式 App 仍走原有 ScrollView 会话流。
        if DemoMode.isOn {
            // 恢复 ScrollView（真实会话流）：正文在 Demo 下已改用 SwiftUI Text（高度首帧确定），
            // 叠加 .defaultScrollAnchor(.top)，首帖头部必然置顶，不再漂移。
            ScrollView {
                detailContent(proxy: nil)
            }
            .defaultScrollAnchor(.top)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground(scheme))
                .navigationTitle(viewModel.thread.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { replyToolbarItem() }
                .toolbar(.hidden, for: .tabBar)
                .task { await viewModel.loadDemo() }
                .onAppear { recordReadHistory() }
                .onDisappear { recordLastReadPost() }
                .fullScreenCover(item: $presentedImage) { item in
                    ImageViewer(url: item.url)
                }
                .sheet(isPresented: $showReply) {
                    ReplySheet(tid: viewModel.thread.id, initial: replyInitial) { _ in }
                }
                .sheet(isPresented: $showUserCard) {
                    if let uid = selectedUser { UserCardSheet(userID: uid) }
                }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    detailContent(proxy: proxy)
                }
                .defaultScrollAnchor(.top)
                .scrollContentBackground(.hidden)
                .background(Color.appBackground(scheme))
                .navigationTitle(viewModel.thread.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { replyToolbarItem() }
                .toolbar(.hidden, for: .tabBar)
                .task { await viewModel.loadFirstPage() }
                .onAppear { recordReadHistory() }
                .onDisappear { recordLastReadPost() }
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
    }

    /// 帖子详情内容区。非 Demo 模式下嵌入 ScrollView；Demo 模式下直接作为普通 VStack。
    @ViewBuilder
    private func detailContent(proxy: ScrollViewProxy?) -> some View {
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
            VStack(spacing: 0) {
                ForEach(Array(pageData.posts.enumerated()), id: \.element.id) { index, post in
                    if onlyAuthorUID == nil || post.authorID == onlyAuthorUID {
                        PostDetailRow(
                            post: post,
                            isOP: index == 0,
                            onlyAuthorUID: $onlyAuthorUID,
                            onUser: { uid in selectedUser = uid; showUserCard = true },
                            onReply: {
                                if let proxy {
                                    withAnimation(nil) { proxy.scrollTo("lastReply", anchor: .bottom) }
                                }
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

    /// 导航栏右上角回复按钮（Demo 与正式模式共用）。
    private func replyToolbarItem() -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showReply = true
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityIdentifier("detail-reply")
        }
    }

    /// 记录进入详情页的浏览历史。
    private func recordReadHistory() {
        ReadHistory.record(tid: viewModel.thread.id,
                           title: viewModel.thread.title,
                           forumID: forumID,
                           context: modelContext)
    }

    /// 记录离开详情页时读到的最后一条回复。
    private func recordLastReadPost() {
        if case .loaded(let page) = viewModel.state,
           let lastPost = page.posts.last {
            ReadHistory.record(tid: viewModel.thread.id,
                               title: viewModel.thread.title,
                               forumID: forumID,
                               lastReadPostID: lastPost.id,
                               context: modelContext)
        }
    }

    /// 把楼层 HTML 正文粗略转纯文本并截断，作为引用预览。
    private func quotePreview(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return String(stripped.prefix(40))
    }
}
