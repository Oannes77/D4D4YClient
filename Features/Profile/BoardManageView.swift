import SwiftUI
import SwiftData

/// 板块管理（我的 → 设置 → 版块管理）。
///
/// 用户在首页展示哪些板块、按什么顺序展示，全部由这里决定，并持久化到 SwiftData：
/// - 上半区「首页展示的板块」（`PinnedForum`）：可上下移动排序、可移除。
/// - 下半区「可添加的板块」：点「添加」加入首页。
///   数据来源优先取论坛真实板块列表（`ForumRepository.sections`）；
///   拉取失败 / 演示模式时回退内置常用板块，保证界面始终可用。
struct BoardManageView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PinnedForum.sortOrder) private var pinned: [PinnedForum]

    @State private var remoteSections: [ForumSection] = []
    @State private var isLoadingRemote = false
    @State private var remoteError: String?

    private let repository: ForumRepositoryProtocol = ForumRepository()

    /// 未固定的候选板块：优先真实板块列表，否则内置常用板块。
    private var candidates: [BoardChipItem] {
        let pinnedIDs = Set(pinned.map(\.fid))
        if !remoteSections.isEmpty {
            return remoteSections
                .filter { !pinnedIDs.contains($0.id) }
                .map { BoardChipItem(id: $0.id, name: $0.name) }
        }
        return ForumBoards.defaults.filter { !pinnedIDs.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                if pinned.isEmpty {
                    Text("还没有添加板块，首页将显示默认板块。")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary(scheme))
                }
                ForEach(0..<pinned.count, id: \.self) { index in
                    let board = pinned[index]
                    HStack {
                        Text(board.name)
                            .foregroundStyle(Color.appTextPrimary(scheme))
                        Spacer()
                        Button { moveUp(index) } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        Button { moveDown(index) } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == pinned.count - 1)
                        Button { remove(board) } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("首页展示的板块（按顺序）")
            } footer: {
                Text("拖动上下箭头调整首页板块顺序；移除后可从下方重新添加。")
            }

            Section {
                if isLoadingRemote {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在加载论坛板块…")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary(scheme))
                    }
                }
                ForEach(candidates, id: \.id) { board in
                    HStack {
                        Text(board.name)
                            .foregroundStyle(Color.appTextPrimary(scheme))
                        Spacer()
                        Button("添加") { add(board) }
                            .font(.subheadline)
                            .foregroundStyle(Color.appPrimary(scheme))
                    }
                }
                if let remoteError {
                    Text(remoteError)
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary(scheme))
                }
            } header: {
                Text("可添加的板块")
            } footer: {
                Text("列表来自论坛导航菜单；加载失败时显示内置常用板块。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground(scheme))
        .navigationTitle("版块管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await reloadRemoteSections() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoadingRemote)
            }
        }
        .task {
            guard !DemoMode.isOn else { return }
            await reloadRemoteSections()
        }
    }

    // MARK: - 排序与增删（本地持久化）

    private func moveUp(_ index: Int) {
        guard index > 0, index < pinned.count else { return }
        let current = pinned[index]
        let previous = pinned[index - 1]
        let tmp = current.sortOrder
        current.sortOrder = previous.sortOrder
        previous.sortOrder = tmp
        try? modelContext.save()
    }

    private func moveDown(_ index: Int) {
        guard index >= 0, index < pinned.count - 1 else { return }
        let current = pinned[index]
        let next = pinned[index + 1]
        let tmp = current.sortOrder
        current.sortOrder = next.sortOrder
        next.sortOrder = tmp
        try? modelContext.save()
    }

    private func remove(_ board: PinnedForum) {
        PinnedForum.unpin(fid: board.fid, context: modelContext)
    }

    private func add(_ board: BoardChipItem) {
        PinnedForum.pin(fid: board.id, name: board.name, context: modelContext)
    }

    // MARK: - 论坛板块列表

    private func reloadRemoteSections() async {
        isLoadingRemote = true
        remoteError = nil
        defer { isLoadingRemote = false }
        do {
            let sections = try await repository.sections()
            remoteSections = sections
            if sections.isEmpty { remoteError = "未解析到板块（将使用内置板块）" }
        } catch {
            remoteError = "加载板块失败：\(error.localizedDescription)"
        }
    }
}
