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

    /// 演示模式：返回手编版块列表，避免联网（仅 `-DemoMode` 调用）。
    func loadDemo() async {
        let sections = [
            ForumSection(id: 14, name: "技术交流", isSubForum: false),
            ForumSection(id: 20, name: "模型下载", isSubForum: false),
            ForumSection(id: 7, name: "心得技巧", isSubForum: false),
            ForumSection(id: 33, name: "设备维修", isSubForum: false),
            ForumSection(id: 5, name: "灌水区", isSubForum: false),
        ]
        state = .loaded(sections)
    }
}
