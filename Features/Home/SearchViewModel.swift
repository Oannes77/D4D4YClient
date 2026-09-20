import Foundation
import Combine

/// 搜索结果视图模型（真实 `search.php`）。
///
/// 结果行复用首页渲染模型 `HomeThreadItem`：
/// 搜索结果页只给出 标题 / 作者 / tid（板块名、正文、图片需进入帖子才知道），
/// 因此 `boardName` 与预览正文为空、统计字段为 nil，界面按字段存在性渲染，不伪造数字。
@MainActor
final class SearchViewModel: ObservableObject {

    enum SearchState: Equatable {
        case idle
        case searching
        case done
        case failed(String)
    }

    @Published private(set) var items: [HomeThreadItem] = []
    @Published private(set) var state: SearchState = .idle

    private let repository: SearchRepositoryProtocol

    init(repository: SearchRepositoryProtocol = SearchRepository()) {
        self.repository = repository
    }

    func search(keyword: String) async {
        state = .searching
        switch await repository.search(keyword: keyword) {
        case .success(let threads):
            items = threads.map { Self.item(from: $0) }
            state = items.isEmpty ? .failed("没有找到相关主题") : .done
        case .failure(let error):
            items = []
            state = .failed(error.localizedDescription)
        }
    }

    private static func item(from thread: ForumThread) -> HomeThreadItem {
        HomeThreadItem(
            id: thread.id,
            boardName: "",                 // 搜索结果页不输出板块名
            title: thread.title,
            authorName: thread.authorName,
            authorID: thread.authorID,
            authorGroup: nil,
            previewBody: "",               // 列表页无正文
            createdAtRaw: thread.createdAtRaw,
            replies: thread.replies ?? 0,
            shares: nil,
            favorites: nil,
            points: nil,
            views: thread.views,
            hasImage: false,
            imageURL: nil,
            hasAttachment: false,
            attachmentCount: 0
        )
    }
}
