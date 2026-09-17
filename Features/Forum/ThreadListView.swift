import SwiftUI
import SwiftData

/// 主题列表（真实数据：forumdisplay.php?fid=xx）。
///
/// UI 方向：
/// - 列表优先，不做 Card；论坛阅读风格。
/// - 左侧保留作者圆形头像（36-44px）。
/// - 标题 / 作者 / 时间 / 回复数 横向信息密度高。
/// - 媒体感知（Sprint 9B 重定义）：列表只显示轻量 📷（正文有图，点按预览首图）/ 📎（含附件，列表不预览）；不做图片数量 / 缩略图 / 图片墙。
struct ThreadListView: View {
    @StateObject private var viewModel: ThreadListViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    /// 本地已屏蔽作者（用于列表隐藏），按 uid 过滤。
    @Query private var blockedUsers: [BlockedUser]
    /// 媒体元数据缓存（按 tid 读取，检测后自动刷新列表行）。
    @Query private var imageCaches: [ThreadMediaCache]

    /// 点击 📷 打开的图片查看器载体。
    @State private var presentedImage: FullScreenImage?

    init(section: ForumSection) {
        _viewModel = StateObject(wrappedValue: ThreadListViewModel(section: section))
    }

    var body: some View {
        List {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("加载主题…")
            case .failed(let message, let detail):
                ErrorRow(message: message, debugDetail: detail, retry: {
                    Task { await viewModel.load(page: viewModel.currentPage) }
                })
            case .loaded(let pageData):
                ForEach(visibleThreads) { thread in
                    threadRow(thread, cache: imageCaches.first(where: { $0.tid == thread.id }))
                }
                paginationFooter(pageInfo: pageData.pageInfo)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground(scheme))
        .navigationTitle(viewModel.section.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ForumThread.self) { thread in
            ThreadDetailView(thread: thread, forumID: viewModel.section.id)
        }
        .fullScreenCover(item: $presentedImage) { item in
            ImageViewer(url: item.url)
        }
        .task {
            if DemoMode.isOn {
                await viewModel.loadDemo()
                if case .loaded(let page) = viewModel.state {
                    await DemoData.seedMedia(for: page.threads, context: modelContext)
                }
            } else {
                await viewModel.loadFirstPage()
                await detectForVisibleThreads()
            }
        }
        .refreshable {
            await viewModel.load(page: viewModel.currentPage)
            await detectForVisibleThreads()
        }
    }

    /// 已过滤被屏蔽作者的可见主题列表（供 ForEach 使用，拆分 body 表达式以通过类型检查）。
    private var visibleThreads: [ForumThread] {
        guard case .loaded(let pageData) = viewModel.state else { return [] }
        let blockedUIDs = Set(blockedUsers.map(\.uid))
        return pageData.threads.filter { thread in
            guard let aid = thread.authorID else { return true }
            return !blockedUIDs.contains(aid)
        }
    }

    /// 列表行：左侧导航 + 右侧轻量媒体标识（📷 预览首图 / 📎 含附件）+ 长按屏蔽菜单。
    @ViewBuilder
    private func threadRow(_ thread: ForumThread, cache: ThreadMediaCache?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(value: thread) {
                ThreadRow(thread: thread, scheme: scheme)
            }
            // 轻量媒体标识（独立承载，不破坏行内文字风格）：
            // 📷 相机：正文有图，点按直接预览第一张；📎 回形针：含附件，列表不预览。
            HStack(spacing: 6) {
                if let cache, cache.hasImage, let url = cache.previewURL {
                    Button {
                        presentedImage = FullScreenImage(url: url)
                    } label: {
                        Image(systemName: "camera.fill")
                            .foregroundStyle(Color.appPrimary(scheme))
                    }
                    .buttonStyle(.borderless)
                }
                if let cache, cache.hasAttachment {
                    Image(systemName: "paperclip")
                        .foregroundStyle(Color.appTextTertiary(scheme))
                }
            }
        }
        .contextMenu {
            if let aid = thread.authorID {
                if BlockedUser.isBlocked(uid: aid, context: modelContext) {
                    Button("取消屏蔽", systemImage: "person.crop.circle.badge.xmark") {
                        BlockedUser.unblock(uid: aid, context: modelContext)
                    }
                } else {
                    Button("屏蔽作者", systemImage: "person.crop.circle.badge.xmark") {
                        BlockedUser.block(uid: aid, username: thread.authorName, context: modelContext)
                    }
                }
            }
        }
    }

    // MARK: - 后台图片检测（方案 B：并发受限，仅当前列表优先主题）

    /// 对当前列表优先显示的主题做图片感知检测。
    /// - 跳过已缓存的 tid（首进列表 / 下拉刷新会重检）；
    /// - 并发默认 4 路；
    /// - 一次性检测上限 cappedAt，避免打开列表即请求几十个帖子。
    private func detectForVisibleThreads() async {
        guard case .loaded(let pageData) = viewModel.state else { return }
        let cached = Set(imageCaches.map(\.tid))
        let tids = pageData.threads.map(\.id)
            .filter { !cached.contains($0) }
            .prefix(ImageMetadataRepository.cappedDetectCount)
        guard !tids.isEmpty else { return }

        let infos = await ImageMetadataRepository.detectAll(Array(tids), maxConcurrent: 4)
        for info in infos {
            ThreadMediaCache.upsert(info, context: modelContext)
        }
    }

    /// 分页栏：上一页 / 当前页 / 总页数 / 下一页（按解析结果可用性显示）
    @ViewBuilder
    private func paginationFooter(pageInfo: PageInfo) -> some View {
        HStack {
            Button("上一页") { Task { await viewModel.goToPreviousPage() } }
                .disabled(pageInfo.previousPageURL == nil)
            Spacer()
            Text("第 \(pageInfo.currentPage) / \(pageInfo.totalPages) 页")
                .font(.footnote)
                .foregroundStyle(Color.appTextSecondary(scheme))
            Spacer()
            Button("下一页") { Task { await viewModel.goToNextPage() } }
                .disabled(pageInfo.nextPageURL == nil)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - ThreadRow

/// 论坛阅读风格行：纯 List 行，禁止 Card。
/// 左侧圆形头像，右侧标题 + 作者 / 时间 / 回复数。
/// 阅读体验优化（Sprint 8）：标题升为 `.body` 更清晰；作者名 / 时间形成信息层级；
/// 回复数用 `bubble.right` 线性图标，弱化色块；行间距随「列表密度」设置联动。
/// 媒体标识（📷 / 📎）由父视图在 NavigationLink 外侧承载，保持行内文字风格不被破坏。
private struct ThreadRow: View {
    let thread: ForumThread
    let scheme: ColorScheme
    @Query private var settings: [LocalSettings]

    private var rowPadding: CGFloat {
        switch settings.first?.listDensity ?? "normal" {
        case "compact": return 4
        case "comfortable": return 12
        default: return 8
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(authorID: thread.authorID, authorName: thread.authorName, size: 42)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 6) {
                    if let type = thread.typeName {
                        Text(type)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appPrimary(scheme))
                    }
                    Text(thread.title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appTextPrimary(scheme))
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(thread.authorName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.appTextSecondary(scheme))
                    if !thread.createdAtRaw.isEmpty {
                        Text(thread.createdAtRaw)
                            .font(.caption2)
                            .foregroundStyle(Color.appTextTertiary(scheme))
                    }
                    Spacer()
                    if let replies = thread.replies, replies > 0 {
                        Label {
                            Text("\(replies)")
                                .font(.caption2)
                                .fontWeight(.medium)
                        } icon: {
                            Image(systemName: "bubble.right")
                        }
                        .foregroundStyle(Color.appTextTertiary(scheme))
                    }
                }
            }
        }
        .padding(.vertical, rowPadding)
    }
}
