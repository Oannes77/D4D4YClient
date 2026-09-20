import Foundation

// MARK: - SearchError
enum SearchError: LocalizedError, Equatable {
    case requiresLogin
    case pageUnavailable
    case network(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .requiresLogin:    return "搜索需要登录：论坛不允许游客搜索，请先登录。"
        case .pageUnavailable:  return "页面不可用：站点返回拦截页（如 Cloudflare），请稍后重试。"
        case .network(let s):   return "网络失败：\(s)"
        case .emptyResult:      return "没有找到相关主题"
        }
    }
}

// MARK: - SearchRepositoryProtocol
protocol SearchRepositoryProtocol {
    /// 按标题搜索（GBK 编码关键词，与论坛 charset 一致）。
    func search(keyword: String) async -> Result<[ForumThread], SearchError>
    /// 按作者搜索（用户卡「搜贴」）。
    func search(authorUID: Int) async -> Result<[ForumThread], SearchError>
}

// MARK: - SearchRepository
/// 搜索数据层：`search.php?srchtxt=<GBK>&srchtype=title&searchsubmit=yes`。
/// 游客态实测返回「您还未登录，无法进行此操作」，此处识别并转为 `.requiresLogin`，不伪造结果。
final class SearchRepository: SearchRepositoryProtocol {

    private let client: HTTPClient
    init(client: HTTPClient = HTTPClient()) { self.client = client }

    func search(keyword: String) async -> Result<[ForumThread], SearchError> {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyResult) }

        // 关键词按 GBK 字节编码（论坛 charset=gbk；UTF-8 中文会乱码）
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_.~"))
        let encoded = DiscuzFormParser.gbkPercent(trimmed, allowed: allowed)
        return await run(path: "search.php?srchtxt=\(encoded)&srchtype=title&searchsubmit=yes")
    }

    /// 按作者搜索（用户卡「搜贴」）：`search.php?srchuid=<uid>&srchfid=all&srchfrom=0&searchsubmit=yes`。
    /// 同样需要登录（论坛不允许游客搜索）。
    func search(authorUID: Int) async -> Result<[ForumThread], SearchError> {
        guard authorUID > 0 else { return .failure(.emptyResult) }
        return await run(path: "search.php?srchuid=\(authorUID)&srchfid=all&srchfrom=0&searchsubmit=yes")
    }

    /// 两种搜索共用的取页 + 解析流程。
    private func run(path: String) async -> Result<[ForumThread], SearchError> {
        do {
            let request = try client.request(path: path)
            let html = try await client.sendText(request)
            switch SearchResultParser.parse(html: html) {
            case .results(let threads): return .success(threads)
            case .noResults:            return .failure(.emptyResult)
            case .requiresLogin:        return .failure(.requiresLogin)
            }
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
