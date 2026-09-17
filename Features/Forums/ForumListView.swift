import SwiftUI
import SwiftData

/// 板块导航（数据：ForumMenuParser）。作为「板块」Tab。
///
/// UI 方向：
/// - 纯文字列表为主，不使用彩色分类图片或商业 App 风格卡片。
/// - 已固定板块使用极简线性 SF Symbol 作为低存在感标记。
struct ForumListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: [SortDescriptor(\PinnedForum.sortOrder, order: .forward)]) private var pinned: [PinnedForum]
    @StateObject private var viewModel = ForumListViewModel()

    private var pinnedFids: Set<Int> { Set(pinned.map(\.fid)) }

    var body: some View {
        NavigationStack {
            List {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("加载版块列表…")
                case .failed(let message, let detail):
                    ErrorRow(message: message, debugDetail: detail, retry: {
                        Task { await viewModel.load() }
                    })
                case .loaded(let sections):
                    ForEach(sections) { section in
                        NavigationLink(value: section) {
                            HStack {
                                Text(section.name)
                                    .foregroundStyle(Color.appTextPrimary(scheme))
                                Spacer()
                                if pinnedFids.contains(section.id) {
                                    Image(systemName: "pin")
                                        .foregroundStyle(Color.appTextTertiary(scheme))
                                        .font(.caption)
                                }
                            }
                        }
                        .listRowBackground(Color.appBackground(scheme))
                        .contextMenu {
                            if pinnedFids.contains(section.id) {
                                Button(role: .destructive) {
                                    PinnedForum.unpin(fid: section.id, context: modelContext)
                                } label: {
                                    Label("取消固定", systemImage: "pin.slash")
                                }
                            } else {
                                Button {
                                    PinnedForum.pin(fid: section.id,
                                                     name: section.name,
                                                     context: modelContext)
                                } label: {
                                    Label("固定到首页", systemImage: "pin")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground(scheme))
            .navigationTitle("板块")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ForumSection.self) { section in
                ThreadListView(section: section)
                    .onAppear {
                        // 记录最近访问板块（本地状态，不触发网络）。
                        VisitedForum.record(fid: section.id,
                                            name: section.name,
                                            context: modelContext)
                    }
            }
            .task {
                if DemoMode.isOn {
                    await viewModel.loadDemo()
                } else {
                    await viewModel.load()
                }
            }
            .refreshable { await viewModel.load() }
        }
    }
}
