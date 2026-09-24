import SwiftUI
import SwiftData
import UIKit

/// 帖子详情（真实数据：viewthread.php?tid=xx）。
///
/// 2026-09-18 Threads 会话视图：
/// - 首帖置顶 + 回复楼层流（ScrollView + ScrollViewReader）。
/// - 每条作者名旁「眼睛」→ 只看该作者（互斥）。
/// - 点「回复」→ 跳最后回复 + 底部回复 Sheet；长按某楼 → 引用并弹回复 Sheet。
/// - 操作栏五图标全部做真实的事：回复 / 分享（菜单：系统分享 + 分享给好友）/
///   收藏（论坛服务器收藏 `my.php?item=favorites`）/ 关注（关注本主题的新回复
///   `my.php?item=attention`）/ 举报（复制链接 + 私信管理员）。
///   （第六项「网页版」已于 2026-09-24 取消：它指向的站内评分功能并不存在。）
/// - 楼层正文图片：点缩略图进全屏画廊，可左右滑浏览本楼层全部图片。
/// - 本地作者屏蔽：命中 `BlockedUser` 时 `PostContent` 显示「该用户内容已隐藏」。
struct ThreadDetailView: View {
    @StateObject private var viewModel: ThreadDetailViewModel
    @StateObject private var replyViewModel: ReplyViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query private var blockedUsers: [BlockedUser]
    /// 收藏状态：来自论坛服务器（`my.php?item=favorites&type=thread`），登录后可用。
    @ObservedObject private var favorites = FavoritesStore.shared
    /// 关注状态：同样来自服务器（`my.php?item=attention`，关注的是**本主题**的新回复）。
    @ObservedObject private var attentions = AttentionStore.shared

    /// 楼层正文多图：点缩略图进全屏画廊，可左右滑浏览本楼层全部图片。
    @State private var presentedGallery: FullScreenGallery?
    @State private var onlyAuthorUID: Int?
    @State private var showReply = false
    @State private var replyInitial = ""
    @State private var selectedUser: Int?
    /// 被点开的作者名（用户卡在资料加载完成前先显示它，避免出现「该用户」占位）。
    @State private var selectedUserName = ""
    @State private var showUserCard = false
    @State private var jumpToLast = false
    /// 「分享给好友」sheet（读好友列表 → 发私信带链接）。
    @State private var showShareToBuddy = false
    /// 举报：复制链接后若已配置收件人，直接打开给管理员的私信。
    @State private var showReportChat = false
    @State private var reportAdminUID = 0
    /// 页面级操作提示（举报 / 收藏的失败原因等）。
    @State private var actionNotice: String?
    /// 站点登录门时弹出的登录页（只有「登录能解决」的情况才会用到）。
    @State private var showLogin = false

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

    /// 该楼作者是否已被本地屏蔽。
    private func isBlocked(_ post: Post) -> Bool {
        guard let uid = post.authorID else { return false }
        return blockedUIDs.contains(uid)
    }

    /// 当前帖子是否已收藏（服务器 `my.php?item=favorites&type=thread`）。
    private var isThreadSaved: Bool {
        favorites.contains(viewModel.thread.id)
    }

    /// 当前帖子是否已关注新回复（服务器 `my.php?item=attention`）。
    private var isThreadAttended: Bool {
        attentions.contains(viewModel.thread.id)
    }

    /// 帖子网页地址（系统分享 / 浏览器打开用）。相对 `HTTPClient.baseURL` 解析，不硬编码域名。
    private var threadWebURL: URL? {
        URL(string: "viewthread.php?tid=\(viewModel.thread.id)",
            relativeTo: HTTPClient.baseURL)?.absoluteURL
    }

    /// 举报私信的**预填草稿**：一段说明 + 该帖链接。
    /// 只是草稿 —— 仍要用户自己点发送，不自动提交、不假装已发出。
    private var reportDraft: String {
        guard let url = threadWebURL else { return "" }
        return "举报帖子：\(viewModel.thread.title)\n\(url.absoluteString)"
    }

    var body: some View {
        // Demo/截图模式：不用 ScrollView，避免 UIKit UITextView 内容高度变化导致
        // SwiftUI ScrollView 滚动位置漂移，保证截图首帖（头像/作者/眼睛/操作栏）
        // 一定可见。正式 App 仍走原有 ScrollView 会话流。
        if DemoMode.isOn {
            // 恢复 ScrollView（真实会话流）：正文在 Demo 下已改用 SwiftUI Text（高度首帧确定），
            // 叠加 .defaultScrollAnchor(.top)，首帖头部必然置顶，不再漂移。
            ScrollViewReader { proxy in
                ScrollView {
                    detailContent(proxy: proxy)
                }
                .defaultScrollAnchor(.top)
                .scrollContentBackground(.hidden)
                .background(Color.appBackground(scheme))
                .task {
                    await favorites.refresh()
                    await attentions.refresh()
                    await viewModel.loadDemo()
                    // 截图「回复楼层」目标：加载完成后滚到页尾，
                    // 让 50 楼回复流与分页条出现在截图里。
                    if jumpToLast {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        proxy.scrollTo("lastReply", anchor: .bottom)
                    }
                }
            }
                .navigationTitle(viewModel.thread.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { replyToolbarItem() }
                .toolbar(.hidden, for: .tabBar)
                .onAppear { recordReadHistory() }
                .onDisappear { recordLastReadPost() }
                .fullScreenCover(item: $presentedGallery) { gallery in
                    ImageViewer(urls: gallery.urls, startIndex: gallery.startIndex)
                }
                .sheet(isPresented: $showReply) {
                    ReplySheet(tid: viewModel.thread.id, initial: replyInitial) { _ in }
                }
                .sheet(isPresented: $showUserCard) {
                    if let uid = selectedUser { UserCardSheet(userID: uid, fallbackName: selectedUserName) }
                }
                .sheet(isPresented: $showShareToBuddy) {
                    if let url = threadWebURL {
                        ShareToBuddySheet(threadURL: url, threadTitle: viewModel.thread.title)
                    }
                }
                .sheet(isPresented: $showReportChat) {
                    NavigationStack {
                        MessageChatView(userID: reportAdminUID,
                                        userName: PreferenceStore.defaultReportAdminName,
                                        initialDraft: reportDraft)
                    }
                }
                .alert("提示", isPresented: Binding(
                    get: { actionNotice != nil },
                    set: { if !$0 { actionNotice = nil } }
                )) {
                    Button("好", role: .cancel) { actionNotice = nil }
                } message: {
                    Text(actionNotice ?? "")
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
                .task {
                    await viewModel.loadFirstPage()
                    await favorites.refresh()
                    await attentions.refresh()
                }
                .onAppear { recordReadHistory() }
                .onDisappear { recordLastReadPost() }
                .fullScreenCover(item: $presentedGallery) { gallery in
                    ImageViewer(urls: gallery.urls, startIndex: gallery.startIndex)
                }
                .sheet(isPresented: $showReply) {
                    ReplySheet(tid: viewModel.thread.id, initial: replyInitial) { _ in }
                }
                .sheet(isPresented: $showUserCard) {
                    if let uid = selectedUser { UserCardSheet(userID: uid, fallbackName: selectedUserName) }
                }
                .sheet(isPresented: $showShareToBuddy) {
                    if let url = threadWebURL {
                        ShareToBuddySheet(threadURL: url, threadTitle: viewModel.thread.title)
                    }
                }
                .sheet(isPresented: $showReportChat) {
                    NavigationStack {
                        MessageChatView(userID: reportAdminUID,
                                        userName: PreferenceStore.defaultReportAdminName,
                                        initialDraft: reportDraft)
                    }
                }
                .alert("提示", isPresented: Binding(
                    get: { actionNotice != nil },
                    set: { if !$0 { actionNotice = nil } }
                )) {
                    Button("好", role: .cancel) { actionNotice = nil }
                } message: {
                    Text(actionNotice ?? "")
                }
                // 登录门专用（正式 App 分支才有意义：演示/截图模式走的是离线夹具）。
                .sheet(isPresented: $showLogin) { LoginView() }
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
                            isBlocked: isBlocked(post),
                            threadURL: threadWebURL,
                            isSaved: isThreadSaved,
                            isAttended: isThreadAttended,
                            onlyAuthorUID: $onlyAuthorUID,
                            onUser: { uid, name in
                                selectedUser = uid
                                selectedUserName = name
                                showUserCard = true
                            },
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
                            onImagesTap: { urls, start in
                                presentedGallery = FullScreenGallery(urls: urls, startIndex: start)
                            },
                            onToggleSave: { toggleSaveThread() },
                            onToggleAttention: { toggleAttendThread() },
                            onUnblock: {
                                // 取消本地拉黑（与论坛管理员的处罚无关）。
                                if let uid = post.authorID {
                                    BlockedUser.unblock(uid: uid, context: modelContext)
                                }
                            },
                            onShareToBuddy: { showShareToBuddy = true },
                            onReport: { reportThread() }
                        )
                        .id(index == 0 ? "firstPost" : "post-\(post.id)")
                        .background(Color.appBackground(scheme))
                        Divider().background(Color.appDivider(scheme))
                    }
                }
            }

            // 分页条：Discuz 每页 50 楼，页尾提供上一页 / 下一页。
            // 「lastReply」锚点必须挂在分页条**之后**：若挂在楼层流末尾，
            // scrollTo(anchor: .bottom) 只会把零高度的锚点对齐到屏幕底部，
            // 其下方的分页条会被挤出屏幕（截图里页码被裁掉半个就是这个原因）。
            pageFooter(pageData.pageInfo)
                .id("lastReply")
        }
    }

    /// 详情页尾部分页条：第 X / N 页 + 上一页 / 下一页。
    /// Demo 模式只展示页码（离线夹具无真实翻页数据），按钮置灰。
    @ViewBuilder
    private func pageFooter(_ info: PageInfo) -> some View {
        HStack {
            Button {
                Task { await viewModel.goToPreviousPage() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline)
            }
            .disabled(DemoMode.isOn || info.previousPageURL == nil)
            .accessibilityIdentifier("detail-page-prev")

            Spacer()

            Text("第 \(info.currentPage) / \(info.totalPages) 页 · 每页 50 楼")
                .font(.footnote)
                .foregroundStyle(Color.appTextSecondary(scheme))

            Spacer()

            Button {
                Task { await viewModel.goToNextPage() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline)
            }
            .disabled(DemoMode.isOn || info.nextPageURL == nil)
            .accessibilityIdentifier("detail-page-next")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.appBackground(scheme))
        .overlay(alignment: .top) {
            Divider().background(Color.appDivider(scheme))
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

    // MARK: - 收藏（论坛服务器真源）

    /// 收藏 / 取消收藏。
    ///
    /// 收藏是**论坛服务器上的数据**（`my.php?item=favorites&type=thread`），需要登录；
    /// 结果以 `FavoritesStore` 的回读确认为准，没确认成功就如实提示。
    private func toggleSaveThread() {
        guard DemoMode.isOn || SessionManager.shared.state.isAuthenticated else {
            actionNotice = "收藏需要登录：登录后收藏会保存到你的 4D4Y 收藏列表里。"
            return
        }
        Task {
            if await favorites.toggle(tid: viewModel.thread.id) == nil {
                actionNotice = favorites.lastError ?? "收藏未能确认，请稍后在「我的 → 收藏」里核对。"
            }
        }
    }

    // MARK: - 关注（论坛服务器真源）

    /// 关注 / 取消关注**本主题的新回复**。
    ///
    /// 站点 PC 模板的原样地址是 `my.php?item=attention&action=add&tid=<tid>` ——
    /// 注意参数是 **tid**：Discuz 7.2 的「关注」关注的是**主题**，不是人。
    /// 需要登录；结果以回读关注列表（`my.php?item=attention`）为唯一判据，
    /// 没确认成功就如实提示，不做乐观更新。
    private func toggleAttendThread() {
        guard DemoMode.isOn || SessionManager.shared.state.isAuthenticated else {
            actionNotice = "关注需要登录：登录后才能在「我的 → 关注」里看到你关注的主题。"
            return
        }
        Task {
            if await attentions.toggle(tid: viewModel.thread.id) == nil {
                actionNotice = attentions.lastError ?? "关注未能确认，请稍后在「我的 → 关注」里核对。"
            }
        }
    }

    // MARK: - 举报

    /// 论坛没有原生举报接口：先把该帖链接复制到剪贴板；
    /// 若已登录，直接打开给管理员（`PreferenceStore.reportAdminUID`，默认 4D4Y / UID 29）的私信，
    /// 并把链接**预填成草稿**（仍需用户自己点发送）。
    /// 未登录只复制链接并如实说明，**绝不假装举报已发出**。
    private func reportThread() {
        guard let url = threadWebURL else {
            actionNotice = "拿不到该帖的网页地址，无法复制链接。"
            return
        }
        UIPasteboard.general.string = url.absoluteString

        let admin = PreferenceStore.shared.reportAdminUID
        if admin > 0, SessionManager.shared.state.isAuthenticated {
            reportAdminUID = admin
            showReportChat = true
        } else if admin > 0 {
            actionNotice = "链接已复制。举报要私信管理员 \(PreferenceStore.defaultReportAdminName)，请先登录后再试。"
        } else {
            actionNotice = "链接已复制。没有可用的举报收件人，请直接粘贴发给管理员。"
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
