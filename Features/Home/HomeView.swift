import SwiftUI

/// 首页：板块主题列表（Threads 风格信息流）。
///
/// 2026-09-18 框架：首页 = 板块主题列表，非 Dashboard。
/// - 顶部板块切换条（Discovery 默认高亮），可左右滑切板块；点选即刷新该板块。
/// - 折叠搜索栏（上推隐藏 / 滚到顶出现）。
/// - 帖子卡片流：标题加粗 + 正文 3 行截断 + 单图 + 附件回形针 + 全图标操作栏。
/// - 右下角紫色 FAB 发帖（仅首页）。
/// - 点击区域收敛：仅 标题/正文/图/附件/回复数 进详情；作者头像/名 弹用户卡。
struct HomeView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var feed: [HomeThreadItem] = []
    @State private var boards = ["Discovery", "Buy & Sell", "Geek Talks", "Smartphone", "PalmOS"]
    @State private var selectedBoard = "Discovery"
    @State private var searchText = ""
    @State private var searchCollapsed = false
    @State private var selectedThread: HomeThreadItem?
    @State private var jumpToLast = false
    @State private var selectedUser: Int?
    @State private var showUserCard = false
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BoardChips(boards: boards, selected: $selectedBoard, onSelect: { board in
                    selectedBoard = board
                    refreshBoard(board)
                })
                CollapsibleSearch(text: $searchText, collapsed: searchCollapsed)

                ScrollView {
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ScrollOffsetKey.self,
                                        value: geo.frame(in: .named("homeScroll")).minY)
                    }
                    .frame(height: 0)

                    if feed.isEmpty {
                        ProgressView(isRefreshing ? "正在刷新 \(selectedBoard) …" : "加载中…")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 80)
                            .foregroundStyle(Color.appTextSecondary(scheme))
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(feed) { item in
                                PostRow(
                                    item: item,
                                    onOpen: { selectedThread = item },
                                    onReply: { selectedThread = item; jumpToLast = true },
                                    onUser: { uid in selectedUser = uid; showUserCard = true }
                                )
                                .background(Color.appBackground(scheme))
                                Divider().background(Color.appDivider(scheme))
                            }
                        }
                    }
                }
                .coordinateSpace(name: "homeScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { y in
                    searchCollapsed = y < -8
                }
            }
            .background(Color.appBackground(scheme))
            .navigationTitle(selectedBoard)
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottomTrailing) {
                ComposeFAB { /* TODO: 发帖 */ }
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
                    jumpToLastReply: jumpToLast
                )
                .onAppear { jumpToLast = false }
            }
            .sheet(isPresented: $showUserCard) {
                if let uid = selectedUser { UserCardSheet(userID: uid) }
            }
        }
        .task {
            if DemoMode.isOn { feed = DemoData.homeFeedDemo() }
        }
    }

    private func refreshBoard(_ board: String) {
        isRefreshing = true
        // Demo：离线无多板块夹具，统一回放 Discovery 样例。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            feed = DemoData.homeFeedDemo()
            isRefreshing = false
        }
    }
}

// MARK: - 滚动偏移偏好（驱动搜索栏折叠）

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
