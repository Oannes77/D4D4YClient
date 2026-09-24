import Foundation
import SwiftData

/// 首页板块主题流视图模型（真实数据驱动）。
///
/// 数据流：`PinnedForum`（SwiftData，决定首页有哪些板块与顺序）
///   → `ForumRepository.threads(fid:page:)`（真实 forumdisplay 解析）
///   → `HomeThreadItem`（渲染模型）
///   → `ImageMetadataRepository` 延迟检测首图 / 附件 / 首帖摘要（写入 ThreadMediaCache，24h）
///
/// 演示模式（`-DemoMode`）由 `HomeView` 直接注入离线样例，不走网络。
@MainActor
final class HomeViewModel: ObservableObject {

    enum FeedState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    // MARK: - 对外状态

    @Published private(set) var items: [HomeThreadItem] = []
    @Published private(set) var state: FeedState = .idle
    @Published private(set) var isLoadingMore = false
    /// 当前板块标题（导航栏用；优先取页面解析出的版块名）
    @Published private(set) var boardTitle: String = ""

    // MARK: - 内部状态

    private let repository: ForumRepositoryProtocol
    private var currentFid: Int?
    private var pageInfo: PageInfo?
    private var context: ModelContext?
    private var detectTask: Task<Void, Never>?

    init(repository: ForumRepositoryProtocol = ForumRepository()) {
        self.repository = repository
    }

    /// 注入 SwiftData 上下文（首页需要读写媒体缓存）。
    func attach(context: ModelContext) {
        self.context = context
    }

    var canLoadMore: Bool { pageInfo?.nextPageURL != nil }

    // MARK: - 加载

    /// 切换板块：加载该板块第一页（已加载过同一板块则不重复请求）。
    func selectBoard(fid: Int, name: String) async {
        if currentFid == fid, case .loaded = state { return }
        boardTitle = name
        await loadFirstPage(fid: fid)
    }

    /// 下拉刷新：重新加载当前板块第一页。
    func refresh() async {
        guard let fid = currentFid else { return }
        await loadFirstPage(fid: fid)
    }

    func loadFirstPage(fid: Int) async {
        currentFid = fid
        state = .loading
        do {
            let page = try await repository.threads(fid: fid, page: 1)
            pageInfo = page.pageInfo
            if let name = page.forumName, !name.isEmpty { boardTitle = name }
            items = makeItems(page.threads)
            state = items.isEmpty ? .failed("该板块暂无主题") : .loaded
            detectMedia(for: page.threads)
        } catch {
            Log.parser.error("首页加载失败: \(String(describing: error), privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// 追加下一页（分页 URL 来自页面解析结果，不自行拼接）。
    func loadMore() async {
        guard let url = pageInfo?.nextPageURL, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repository.threads(pageURL: url)
            pageInfo = page.pageInfo
            items.append(contentsOf: makeItems(page.threads))
            detectMedia(for: page.threads)
        } catch {
            Log.parser.error("首页加载更多失败: \(String(describing: error), privacy: .public)")
        }
    }

    /// 列表滚到末尾时触发（由 `HomeView` 的 onAppear 调用）。
    func loadMoreIfNeeded(current item: HomeThreadItem) async {
        guard items.last?.id == item.id else { return }
        await loadMore()
    }

    // MARK: - 渲染模型转换

    /// `ForumThread` → `HomeThreadItem`：只填列表页真实存在的字段，
    /// 论坛列表不输出的（转发 / 收藏 / 积分 / 查看数）一律 nil，不伪造。
    private func makeItems(_ threads: [ForumThread]) -> [HomeThreadItem] {
        threads.map { thread in
            let cache = context.flatMap { ThreadMediaCache.cache(for: thread.id, context: $0) }
            let title = thread.title
            return HomeThreadItem(
                id: thread.id,
                boardName: boardTitle,
                title: title,
                authorName: thread.authorName,
                authorID: thread.authorID,
                authorGroup: nil,
                previewBody: cache?.previewText ?? "",
                createdAtRaw: displayDate(of: thread),
                replies: thread.replies ?? 0,
                shares: nil,
                favorites: nil,
                points: nil,
                views: thread.views,
                hasImage: cache?.hasImage ?? false,
                imageURL: cache?.previewURL,
                hasAttachment: cache?.hasAttachment ?? false,
                attachmentCount: 0
            )
        }
    }

    /// 列表时间：优先发帖日期，缺失时用最后回复时间。
    private func displayDate(of thread: ForumThread) -> String {
        let raw = thread.createdAtRaw.isEmpty ? (thread.lastReplyAtRaw ?? "") : thread.createdAtRaw
        return raw.isEmpty ? "" : raw
    }

    // MARK: - 媒体与摘要延迟检测

    /// 只对「未缓存或已过期」的主题发起检测，最多 `cappedDetectCount` 条。
    private func detectMedia(for threads: [ForumThread]) {
        guard let context else { return }
        let fresh = Set(((try? context.fetch(FetchDescriptor<ThreadMediaCache>())) ?? [])
            .filter { $0.isFresh }
            .map(\.tid))
        let pending = threads.map(\.id).filter { !fresh.contains($0) }
        guard !pending.isEmpty else { return }
        let limited = Array(pending.prefix(ImageMetadataRepository.cappedDetectCount))

        detectTask?.cancel()
        detectTask = Task { [weak self] in
            let infos = await ImageMetadataRepository.detectAll(limited)
            guard !infos.isEmpty else { return }
            guard let self else { return }
            self.apply(infos)
        }
    }

    /// 检测结果入库并回写到已展示的行（图片 / 附件 / 首帖摘要）。
    private func apply(_ infos: [ThreadMediaInfo]) {
        guard let context else { return }
        for info in infos { ThreadMediaCache.upsert(info, context: context) }
        let dict = Dictionary(uniqueKeysWithValues: infos.map { ($0.tid, $0) })
        items = items.map { item in
            guard let info = dict[item.id] else { return item }
            return item.updated(with: info)
        }
    }
}
