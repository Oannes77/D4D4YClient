import SwiftUI
import SwiftData

/// 首页：板块主题列表（Threads 风格信息流）。
///
/// 2026-09-18 框架：首页 = 板块主题列表，非 Dashboard。
/// - 顶部板块切换条（来自 SwiftData `PinnedForum`，用户顺序），点选即刷新该板块。
/// - 折叠搜索栏（上推隐藏 / 滚到顶出现），回车进入搜索结果页。
/// - 帖子卡片流：标题加粗 + 正文 3 行截断 + 单图 + 附件回形针 + 全图标操作栏。
/// - 下拉刷新 + 滚到末尾自动加载下一页（分页 URL 由页面解析给出）。
/// - 右下角紫色 FAB 发帖（仅首页）。
/// - 点击区域收敛：仅 标题/正文/图/附件/回复数 进详情；作者头像/名 弹用户卡。
struct HomeView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PinnedForum.sortOrder) private var pinned: [PinnedForum]
    @StateObject private var viewModel = HomeViewModel()

    @State private var selectedFid: Int = 2
    @State private var searchText = ""
    @State private var searchCollapsed = false
    @State private var searchRequest: SearchRequest?
    /// 演示模式专用：离线样例流（不触发网络）。
    @State private var demoFeed: [HomeThreadItem] = []
    @State private var selectedThread: HomeThreadItem?
    @State private var jumpToLast = false
    @State private var selectedUser: Int?
    @State private var showUserCard = false
    @State private var showCompose = false

    /// 首页板块：用户固定的板块（按 sortOrder）；一个都没有时回落默认三个。
    private var boards: [BoardChipItem] {
        let list = pinned.map { BoardChipItem(id: $0.fid, name: $0.name) }
        return list.isEmpty ? Self.defaultBoards : list
    }

    private var feed: [HomeThreadItem] { DemoMode.isOn ? demoFeed : viewModel.items }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BoardChips(boards: boards, selectedID: $selectedFid) { item in
                    selectedFid = item.id
                    VisitedForum.record(fid: item.id, name: item.name, context: modelContext)
                    Task { await viewModel.selectBoard(fid: item.id, name: item.name) }
                }
                CollapsibleSearch(
                    text: $searchText,
                    collapsed: searchCollapsed,
                    placeholder: "搜索 \(viewModel.boardTitle.isEmpty ? "4D4Y" : viewModel.boardTitle)",
                    onSubmit: submitSearch
                )

                content
            }
            .background(Color.appBackground(scheme))
            .navigationTitle(viewModel.boardTitle.isEmpty ? "首页" : viewModel.boardTitle)
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottomTrailing) {
                ComposeFAB { showCompose = true }
                    .padding(20)
            }
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
                if let uid = selectedUser { UserCardSheet(userID: uid) }
            }
            .sheet(isPresented: $showCompose) {
                NewPostView(defaultFid: selectedFid)
            }
        }
        .task { await bootstrap() }
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
            searchCollapsed = y < -8
        }
    }

    private var feedList: some View {
        LazyVStack(spacing: 0) {
            ForEach(feed) { item in
                PostRow(
                    item: item,
                    onOpen: { selectedThread = item },
                    onReply: { selectedThread = item; jumpToLast = true },
                    onUser: { uid in selectedUser = uid; showUserCard = true }
                )
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

    private func submitSearch() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        searchRequest = SearchRequest(keyword: keyword)
    }

    private static let defaultBoards: [BoardChipItem] = ForumBoards.defaults
}

// MARK: - 搜索请求（navigationDestination 需要 Identifiable）

private struct SearchRequest: Identifiable {
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
