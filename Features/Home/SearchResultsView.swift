import SwiftUI
import SwiftData

/// 搜索结果页（首页顶部搜索栏回车 → 结果列表）。
///
/// 复用信息流卡片 `PostRow`，保持与首页一致的 Threads 视觉语言；
/// 顶部显示关键词与结果数。演示模式（`DemoMode.isOn`）使用离线样例，不发起网络请求。
struct SearchResultsView: View {
    let keyword: String

    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var modelContext
    /// 本地收藏（书签）：与首页 / 详情页共用同一份数据。
    @Query private var savedThreads: [SavedThread]
    @StateObject private var viewModel = SearchViewModel()
    @State private var selectedThread: HomeThreadItem?
    @State private var selectedUser: Int?
    @State private var selectedUserName = ""
    @State private var showUserCard = false

    init(keyword: String = "X1C") {
        self.keyword = keyword
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
                            ProgressView("正在搜索 “\(keyword)” …")
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
            guard !DemoMode.isOn else { return }
            await viewModel.search(keyword: keyword)
        }
        .sheet(isPresented: $showUserCard) {
            if let uid = selectedUser { UserCardSheet(userID: uid, fallbackName: selectedUserName) }
        }
    }

    private var header: some View {
        HStack {
            Text("“\(keyword)” 的搜索结果")
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

    private var savedIDs: Set<Int> { Set(savedThreads.map(\.tid)) }

    /// 切换本地收藏（只写本机 SwiftData，不伪造服务器收藏成功）。
    private func toggleSave(_ item: HomeThreadItem) {
        SavedThread.toggle(tid: item.id,
                           title: item.title,
                           boardName: item.boardName.isEmpty ? nil : item.boardName,
                           authorName: item.authorName,
                           context: modelContext)
    }
}
