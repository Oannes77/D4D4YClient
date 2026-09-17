import Foundation

@MainActor
final class ThreadListViewModel: ObservableObject {
    @Published private(set) var state: Loadable<ThreadListPage> = .idle
    @Published var currentPage: Int = 1

    let section: ForumSection
    private let repository: ForumRepositoryProtocol

    init(section: ForumSection, repository: ForumRepositoryProtocol = ForumRepository()) {
        self.section = section
        self.repository = repository
    }

    func loadFirstPage() async {
        await load(page: 1)
    }

    func load(page: Int) async {
        currentPage = page
        state = .loading
        do {
            let pageData = try await repository.threads(fid: section.id, page: page)
            if pageData.threads.isEmpty {
                state = .failed(message: "主题列表为空",
                                debugDetail: "HTTP 成功但 ThreadListParser 输出 0 行")
            } else {
                state = .loaded(pageData)
            }
        } catch {
            Log.parser.error("ThreadList load 失败: \(String(describing: error), privacy: .public)")
            state = .failed(error)
        }
    }

    func goToNextPage() async {
        guard let next = state.value?.pageInfo.nextPageURL else { return }
        await load(pageURL: next)
    }

    func goToPreviousPage() async {
        guard let prev = state.value?.pageInfo.previousPageURL else { return }
        await load(pageURL: prev)
    }

    /// 翻页直接使用 Parser 解析出的站内相对分页 URL，不再自行重建 URL。
    private func load(pageURL: String) async {
        state = .loading
        do {
            let pageData = try await repository.threads(pageURL: pageURL)
            if pageData.threads.isEmpty {
                state = .failed(message: "主题列表为空",
                                debugDetail: "HTTP 成功但 ThreadListParser 输出 0 行")
            } else {
                currentPage = pageData.pageInfo.currentPage
                state = .loaded(pageData)
            }
        } catch {
            Log.parser.error("ThreadList load 失败: \(String(describing: error), privacy: .public)")
            state = .failed(error)
        }
    }
}
