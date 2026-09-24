import Foundation

@MainActor
final class ThreadDetailViewModel: ObservableObject {
    @Published private(set) var state: Loadable<ThreadPage> = .idle

    let thread: ForumThread
    private let repository: ForumRepositoryProtocol

    init(thread: ForumThread, repository: ForumRepositoryProtocol = ForumRepository()) {
        self.thread = thread
        self.repository = repository
        // 演示模式：初始化即同步就绪，跳过 idle→loaded 的内容高度跳变，
        // 避免 SwiftUI ScrollView 在内容骤然变长后初始 offset 漂移到长帖中部。
        if DemoMode.isOn, let pageData = DemoData.loadViewthreadFixture(tid: thread.id) {
            state = .loaded(pageData)
        }
    }

    func loadFirstPage() async {
        await load(page: 1)
    }

    func load(page: Int) async {
        state = .loading
        do {
            let pageData = try await repository.posts(tid: thread.id, page: page)
            state = .loaded(pageData)
        } catch {
            Log.parser.error("ThreadDetail load 失败: \(String(describing: error), privacy: .public)")
            state = .failed(error)
        }
    }

    func goToNextPage() async {
        guard let next = state.value?.pageInfo.nextPageURL else { return }
        await load(pageURL: next)
    }

    /// 演示模式：离线解析仓库内 viewthread 夹具，避免联网（仅 `-DemoMode` 调用）。
    /// 夹具按 tid 选：纯文字帖 193033、带 5 张附件图的 439576（见 `DemoData.viewthreadFixtures`）。
    func loadDemo() async {
        guard let pageData = DemoData.loadViewthreadFixture(tid: thread.id) else {
            state = .failed(message: "演示数据缺失", debugDetail: "viewthread 夹具未找到")
            return
        }
        state = .loaded(pageData)
    }

    func goToPreviousPage() async {
        guard let prev = state.value?.pageInfo.previousPageURL else { return }
        await load(pageURL: prev)
    }

    /// 回复成功后跳到末页：Discuz 会将越界 page 钳制到最后一页，新楼层即在此页。
    func refreshToLastPage() async {
        await load(page: 9999)
    }

    /// 翻页直接使用 Parser 解析出的站内相对分页 URL，不再自行重建 URL。
    private func load(pageURL: String) async {
        state = .loading
        do {
            let pageData = try await repository.posts(pageURL: pageURL)
            state = .loaded(pageData)
        } catch {
            Log.parser.error("ThreadDetail load 失败: \(String(describing: error), privacy: .public)")
            state = .failed(error)
        }
    }
}
