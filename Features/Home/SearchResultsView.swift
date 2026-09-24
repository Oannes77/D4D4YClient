import SwiftUI
import SwiftData

/// 搜索结果页。
///
/// 两种入口：
/// - 首页顶部搜索栏回车 → 按关键词（`keyword`）；
/// - 用户卡「搜贴」→ 按作者（`authorUID`，走 `search.php?srchuid=`）。
///
/// 复用信息流卡片 `PostRow`，保持与首页一致的 Threads 视觉语言；
/// 顶部显示搜索条件与结果数。演示模式（`DemoMode.isOn`）使用离线样例，不发起网络请求。
struct SearchResultsView: View {
    let keyword: String
    /// 按作者搜索时的作者 uid；非 nil 时忽略 `keyword`。
    let authorUID: Int?
    /// 作者名（仅用于标题展示，可为空）。
    let authorName: String?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var modelContext
    /// 收藏状态（论坛服务器真源 `my.php?item=favorites`，登录后可用）：与首页 / 详情页共用同一份数据。
    @ObservedObject private var favorites = FavoritesStore.shared
    @StateObject private var viewModel = SearchViewModel()
    @State private var selectedThread: HomeThreadItem?
    @State private var selectedUser: Int?
    @State private var selectedUserName = ""
    @State private var showUserCard = false
    /// 收藏需要登录时弹出的登录页。
    @State private var showLogin = false
    /// 收藏结果提示（失败原因）。
    @State private var saveNotice: String?

    init(keyword: String = "X1C", authorUID: Int? = nil, authorName: String? = nil) {
        self.keyword = keyword
        self.authorUID = authorUID
        self.authorName = authorName
    }

    /// 顶部条件文案。
    private var conditionText: String {
        if authorUID != nil { return "\(authorName ?? "该用户") 的主题" }
        return "“\(keyword)” 的搜索结果"
    }

    /// 加载中文案。
    private var loadingText: String {
        if authorUID != nil { return "正在读取 \(authorName ?? "该用户") 的主题…" }
        return "正在搜索 “\(keyword)” …"
    }

    private var results: [HomeThreadItem] {
        DemoMode.isOn ? DemoData.homeFeedDemo() : viewModel.items
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                if DemoMode.isOn {
                    resultList
                } else {
                    switch viewModel.state {
                    case .idle, .searching:
                        if viewModel.items.isEmpty {
                            ProgressView(loadingText)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 60)
                                .foregroundStyle(Color.appTextSecondary(scheme))
                        } else {
                            resultList
                        }
                    case .done:
                        resultList
                    case .failed(let message):
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary(scheme))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 60)
                    }
                }
            }
        }
        .background(Color.appBackground(scheme))
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedThread) { item in
            ThreadDetailView(
                thread: ForumThread(
                    id: item.id, title: item.title, typeName: nil,
                    authorName: item.authorName, authorID: item.authorID,
                    createdAt: nil, createdAtRaw: item.createdAtRaw,
                    replies: item.replies, views: item.views,
                    lastReplyUserName: nil, lastReplyAtRaw: nil
                )
            )
        }
        .task {
            await favorites.refresh()
            guard !DemoMode.isOn else { return }
            if let authorUID {
                await viewModel.search(authorUID: authorUID)
            } else {
                await viewModel.search(keyword: keyword)
            }
        }
        .sheet(isPresented: $showUserCard) {
            if let uid = selectedUser { UserCardSheet(userID: uid, fallbackName: selectedUserName) }
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

    private var header: some View {
        HStack {
            Text(conditionText)
                .font(.footnote)
                .foregroundStyle(Color.appTextSecondary(scheme))
            Spacer()
            Text("\(results.count) 条")
                .font(.footnote)
                .foregroundStyle(Color.appTextTertiary(scheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var resultList: some View {
        LazyVStack(spacing: 0) {
            ForEach(results) { item in
                PostRow(
                    item: item,
                    onOpen: { selectedThread = item },
                    onReply: { selectedThread = item },
                    onUser: { uid, name in
                        selectedUser = uid
                        selectedUserName = name
                        showUserCard = true
                    },
                    isSaved: savedIDs.contains(item.id),
                    threadURL: HTTPClient.absoluteURL(path: "viewthread.php?tid=\(item.id)"),
                    onToggleSave: { toggleSave(item) }
                )
                Divider().background(Color.appDivider(scheme))
            }
        }
    }

    private var savedIDs: Set<Int> { favorites.tids }

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
