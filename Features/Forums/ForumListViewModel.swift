import Foundation

@MainActor
final class ForumListViewModel: ObservableObject {
    @Published private(set) var state: Loadable<[ForumSection]> = .idle

    private let repository: ForumRepositoryProtocol

    init(repository: ForumRepositoryProtocol = ForumRepository()) {
        self.repository = repository
    }

    func load() async {
        state = .loading
        do {
            let sections = try await repository.sections()
            if sections.isEmpty {
                state = .failed(message: "版块列表为空",
                                debugDetail: "ForumMenuParser 未解析到任何版块（#silder_l 缺失？）")
            } else {
                state = .loaded(sections)
            }
        } catch {
            Log.parser.error("ForumList load 失败: \(String(describing: error), privacy: .public)")
            state = .failed(error)
        }
    }
}
