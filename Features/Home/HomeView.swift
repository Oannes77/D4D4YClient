import SwiftUI
import SwiftData

/// 首页：板块主题列表（Threads 风格信息流）。
///
/// 2026-09-18 框架：首页 = 板块主题列表，非 Dashboard。
/// - 顶部板块切换条（来自 SwiftData `PinnedForum`，用户顺序）：**点击胶囊**进入该板块并刷新最近动态，
///   **在胶囊条上左右滑**切换到上一个 / 下一个板块，滑块自动居中到当前胶囊。
/// - 搜索栏：**默认收起**（省出信息位），**下拉回弹才展开**；一旦向上滚内容即自动收起。
///   回车进入搜索结果页。
/// - 发帖入口：搜索框下方的 Threads 风格一条（头像 + 「发新帖…」胶囊），点它进发帖页。
///   ⚠️ 2026-09-24 起**取消右下角紫色悬浮按钮（FAB）** —— FAB 固定悬浮必然压住列表正文
///   （验收截图里盖住了第 2 条的标题与摘要），改由这条常驻入口承担同一功能。
/// - 帖子卡片流：标题加粗 + 正文 3 行截断 + 单图 + 附件回形针 + 全图标操作栏。
/// - 下拉刷新 + 滚到末尾自动加载下一页（分页 URL 由页面解析给出）。
/// - 点击区域收敛：仅 标题/正文/图/附件/回复数 进详情；作者头像/名 弹用户卡。
struct HomeView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PinnedForum.sortOrder) private var pinned: [PinnedForum]
    /// 收藏状态（论坛服务器真源 `my.php?item=favorites`，登录后可用）：列表行星标与详情页共用同一份数据。
    @ObservedObject private var favorites = FavoritesStore.shared
    /// 本地已拉黑作者（纯客户端行为，与论坛侧处罚无关）。
    @Query private var blockedUsers: [BlockedUser]
    /// 当前会话：发帖入口左侧头像用（登录后换真人头像）。
    /// 直接观察共享单例而不是走 `@EnvironmentObject` —— 首页在各处（含截图路由）被复用，
    /// 少一个「环境里没注入就崩」的隐患。
    @ObservedObject private var session = SessionManager.shared
    @StateObject private var viewModel = HomeViewModel()

    @State private var selectedFid: Int = 2
    @State private var searchText = ""
    /// 搜索栏默认**收起**（只在首页顶部下拉回弹时展开）。
    @State private var searchCollapsed = true
    @State private var searchRequest: SearchRequest?
    /// 演示模式专用：离线样例流（不触发网络）。
    @State private var demoFeed: [HomeThreadItem] = []
    /// 演示模式专用：离线夹具解析出的筛选条（同一个 `BoardFilterParser`）。
    @State private var demoFilterBar: BoardFilterBar?
    @State private var selectedThread: HomeThreadItem?
    @State private var jumpToLast = false
    @State private var selectedUser: Int?
    /// 被点开的作者名（用户卡在资料加载完成前先显示它，避免出现「该用户」占位）。
    @State private var selectedUserName = ""
    @State private var showUserCard = false
    @State private var showCompose = false
    /// 收藏需要登录时弹出的登录页。
    @State private var showLogin = false
    /// 收藏结果提示（失败原因）。
    @State private var saveNotice: String?

    /// 首页板块：用户固定的板块（按 sortOrder）；一个都没有时回落默认三个。
    private var boards: [BoardChipItem] {
        let list = pinned.map { BoardChipItem(id: $0.fid, name: $0.name) }
        return list.isEmpty ? Self.defaultBoards : list
    }

    private var feed: [HomeThreadItem] {
        // 演示模式：初始用手写样例流（离线、截图稳定）；**一旦在演示里点了筛选**，
        // `viewModel.items` 会有真实结果，此时改用真实结果 —— 筛选条就不会是「点了没反应」的死控件。
        DemoMode.isOn && viewModel.items.isEmpty ? demoFeed : viewModel.items
    }

    /// 当前筛选条：线上取页面解析结果；演示模式取离线夹具里同一条（同一个解析器）。
    private var activeFilterBar: BoardFilterBar? {
        DemoMode.isOn ? (demoFilterBar ?? viewModel.filterBar) : viewModel.filterBar
    }

    /// 当前用户 UID（未登录 / 拿不到时为 nil ⇒ 头像走中性默认图标，不发多余请求）。
    private var currentUserID: Int? {
        guard let uid = session.state.session?.uid, uid > 0 else { return nil }
        return uid
    }

    /// 当前用户名（头像回退时只在无障碍标签里用，不显示占位文字）。
    private var currentUserName: String { session.state.session?.username ?? "" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BoardChips(
                    boards: boards,
                    selectedID: $selectedFid,
                    onSelect: { select($0) },
                    onSwipe: { switchBoard(by: $0) }
                )

                // 板块筛选条：**分类在前、排序时间在后**，全部来自板块页自身链接。
                // 演示模式用同一条（从离线夹具 PC 页面解析），保证「演示跑的 = 线上跑的」。
                if let bar = activeFilterBar, !bar.isEmpty {
                    BoardFilterBarView(bar: bar) { option in
                        Task { await viewModel.applyFilter(option) }
                    }
                }

                CollapsibleSearch(
                    text: $searchText,
                    collapsed: searchCollapsed,
                    placeholder: "搜索 \(viewModel.boardTitle.isEmpty ? "4D4Y" : viewModel.boardTitle)",
                    onSubmit: submitSearch
                )

                // 发帖入口（取代原右下角 FAB —— FAB 悬浮会压住列表正文）。
                ComposeEntryBar(
                    authorID: currentUserID,
                    authorName: currentUserName
                ) { showCompose = true }

                content
            }
            .background(Color.appBackground(scheme))
            .navigationTitle(viewModel.boardTitle.isEmpty ? "首页" : viewModel.boardTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedThread) { item in
                ThreadDetailView(
                    thread: ForumThread(
                        id: item.id, title: item.title, typeName: nil,
                        authorName: item.authorName, authorID: item.authorID,
                        createdAt: nil, createdAtRaw: item.createdAtRaw,
                        replies: item.replies, views: item.views,
                        lastReplyUserName: nil, lastReplyAtRaw: nil
                    ),
                    forumID: selectedFid,
                    jumpToLastReply: jumpToLast
                )
                .onAppear { jumpToLast = false }
            }
            .navigationDestination(item: $searchRequest) { request in
                SearchResultsView(keyword: request.keyword)
            }
            .sheet(isPresented: $showUserCard) {
                if let uid = selectedUser { UserCardSheet(userID: uid, fallbackName: selectedUserName) }
            }
            .sheet(isPresented: $showCompose) {
                NewPostView(defaultFid: selectedFid)
            }
            .sheet(isPresented: $showLogin) { LoginView() }
            .alert("提示", isPresented: Binding(
                get: { saveNotice != nil },
                set: { if !$0 { saveNotice = nil } }
            )) {
                Button("好", role: .cancel) { saveNotice = nil }
            } message: {
                Text(saveNotice ?? "")
            }
        }
        .task {
            await bootstrap()
            await favorites.refresh()
        }
        .refreshable {
            guard !DemoMode.isOn else { return }
            await viewModel.refresh()
        }
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        ScrollView {
            GeometryReader { geo in
                Color.clear
                    .preference(key: ScrollOffsetKey.self,
                                value: geo.frame(in: .named("homeScroll")).minY)
            }
            .frame(height: 0)

            if DemoMode.isOn {
                feedList
            } else {
                switch viewModel.state {
                case .idle, .loading:
                    if viewModel.items.isEmpty {
                        ProgressView("加载中…")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 80)
                            .foregroundStyle(Color.appTextSecondary(scheme))
                    } else {
                        feedList
                    }
                case .loaded:
                    feedList
                case .failed(let message):
                    failureView(message)
                }
            }
        }
        .coordinateSpace(name: "homeScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { y in
            // 搜索栏默认收起；**下拉回弹**（内容被拽过顶，y > 4）才展开，
            // 一旦向上滚内容（y < -4）就收起。
            // 两个阈值分开、且中间不动作 ⇒ 回弹到位时不会反复抖。
            if y > 4, searchCollapsed {
                searchCollapsed = false
            } else if y < -4, !searchCollapsed {
                searchCollapsed = true
            }
        }
    }

    private var feedList: some View {
        LazyVStack(spacing: 0) {
            ForEach(feed) { item in
                Group {
                    if let uid = item.authorID, blockedUIDs.contains(uid) {
                        // 本地拉黑：主题行替换为占位，可就地取消（不显示标题 / 摘要）。
                        BlockedPlaceholderRow(authorName: item.authorName) {
                            BlockedUser.unblock(uid: uid, context: modelContext)
                        }
                    } else {
                        PostRow(
                            item: item,
                            onOpen: { selectedThread = item },
                            onReply: { selectedThread = item; jumpToLast = true },
                            onUser: { uid, name in
                                selectedUser = uid
                                selectedUserName = name
                                showUserCard = true
                            },
                            isSaved: savedIDs.contains(item.id),
                            threadURL: Self.threadURL(for: item.id),
                            onToggleSave: { toggleSave(item) }
                        )
                    }
                }
                .background(Color.appBackground(scheme))
                .onAppear {
                    guard !DemoMode.isOn else { return }
                    Task { await viewModel.loadMoreIfNeeded(current: item) }
                }
                Divider().background(Color.appDivider(scheme))
            }

            if viewModel.isLoadingMore {
                ProgressView()
                    .padding(.vertical, 16)
            }
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title)
                .foregroundStyle(Color.appTextTertiary(scheme))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary(scheme))
                .multilineTextAlignment(.center)
            Button("重试") {
                Task { await viewModel.refresh() }
            }
            .font(.subheadline)
            .foregroundStyle(Color.appPrimary(scheme))
        }
        .padding(.horizontal, 32)
        .padding(.top, 80)
    }

    // MARK: - 启动

    private func bootstrap() async {
        if DemoMode.isOn {
            demoFeed = DemoData.homeFeedDemo()
            // 筛选条也从**离线夹具的真实 PC 页面**里解析（不是手编一张表）：
            // 这样截图里看到的分类顺序、数量与线上完全一致。
            demoFilterBar = DemoData.loadForumDisplayFixture()?.filterBar
            return
        }
        viewModel.attach(context: modelContext)
        seedDefaultBoardsIfNeeded()
        guard let first = boards.first else { return }
        selectedFid = first.id
        await viewModel.selectBoard(fid: first.id, name: first.name)
    }

    /// 首次启动（用户还没配置板块）时写入默认板块，保证首页有内容。
    private func seedDefaultBoardsIfNeeded() {
        guard pinned.isEmpty else { return }
        for board in Self.defaultBoards {
            PinnedForum.pin(fid: board.id, name: board.name, context: modelContext)
        }
    }

    /// 选中某个板块：记录访问 + 刷新该板块内容（演示模式不联网）。
    private func select(_ item: BoardChipItem) {
        selectedFid = item.id
        VisitedForum.record(fid: item.id, name: item.name, context: modelContext)
        guard !DemoMode.isOn else { return }
        Task { await viewModel.selectBoard(fid: item.id, name: item.name) }
    }

    /// 在胶囊条上左右滑：切换到上一个 / 下一个板块（到头即停，不循环）。
    private func switchBoard(by offset: Int) {
        guard let index = boards.firstIndex(where: { $0.id == selectedFid }) else { return }
        let next = index + offset
        guard boards.indices.contains(next) else { return }
        select(boards[next])
    }

    private func submitSearch() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        searchRequest = SearchRequest(keyword: keyword)
    }

    private static let defaultBoards: [BoardChipItem] = ForumBoards.defaults

    // MARK: - 收藏与拉黑

    /// 已收藏的 tid（服务器收藏）。
    private var savedIDs: Set<Int> { favorites.tids }

    /// 本地已拉黑作者的 uid 集合（`BlockedUser`）。
    private var blockedUIDs: Set<Int> { Set(blockedUsers.map(\.uid)) }

    /// 帖子网页地址：由 tid 现算，指向论坛本站（系统分享用）。
    private static func threadURL(for tid: Int) -> URL? {
        HTTPClient.absoluteURL(path: "viewthread.php?tid=\(tid)")
    }

    /// 切换收藏：写论坛服务器（需要登录），结果以回读确认为准。
    private func toggleSave(_ item: HomeThreadItem) {
        guard DemoMode.isOn || SessionManager.shared.state.isAuthenticated else {
            showLogin = true
            return
        }
        Task {
            if await favorites.toggle(tid: item.id) == nil {
                saveNotice = favorites.lastError ?? "收藏未能确认，请稍后在「我的 → 收藏」里核对。"
            }
        }
    }
}

// MARK: - 搜索请求（navigationDestination 需要 Identifiable）

private struct SearchRequest: Identifiable, Hashable {
    let id = UUID()
    let keyword: String
}

// MARK: - 滚动偏移偏好（驱动搜索栏折叠）

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
