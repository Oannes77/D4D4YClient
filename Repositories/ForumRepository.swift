import Foundation

/// 数据仓库协议。ViewModel 只依赖此协议，不接触 HTTPClient 与 Parser。
protocol ForumRepositoryProtocol {
    /// 版块列表（取自页面内置导航菜单）
    func sections() async throws -> [ForumSection]
    /// 某版块的**主题分类**（发帖时选 `typeid` 用；站点每个版块不同，运行时解析、不硬编码）。
    /// 该版块没开分类时返回空数组。
    func categories(fid: Int) async throws -> [BoardCategory]
    /// 某版块第一页主题列表（fid 已知，首屏无分页 URL 可用）
    func threads(fid: Int, page: Int) async throws -> ThreadListPage
    /// 请求 PaginationParser 解析出的站内相对分页 URL（已按 4d4y.com/forum/ 校验）
    func threads(pageURL: String) async throws -> ThreadListPage
    /// 某主题第一页楼层（tid 已知，首屏无分页 URL 可用）
    func posts(tid: Int, page: Int) async throws -> ThreadPage
    /// 请求 PaginationParser 解析出的站内相对分页 URL（已按 4d4y.com/forum/ 校验）
    func posts(pageURL: String) async throws -> ThreadPage
}

/// 默认实现：HTTPClient（网络）+ *Parser（HTML）→ Model。
final class ForumRepository: ForumRepositoryProtocol {

    private let client: HTTPClient

    init(client: HTTPClient = HTTPClient()) {
        self.client = client
    }

    /// index.php 被 Cloudflare 稳定拦截，因此版块菜单从任意一个
    /// 正常可达的 forumdisplay 页面内的 #silder_l 导航解析。
    func sections() async throws -> [ForumSection] {
        let request = try client.request(path: "forumdisplay.php?fid=14")
        let html = try await client.sendText(request)
        return try ForumMenuParser.parse(html: html)
    }

    /// 主题分类：从**该板块页自身的分类链接**里解析（游客可见，不需要登录）。
    ///
    /// 为什么不去解析发帖表单里的 `typeid` 下拉？那条路要登录才看得到；
    /// 而板块页的分类链接给出的 `typeid` 与分类名是**同一份数据**，
    /// 且与站点一致（分类列表本来就是按板块配的）。
    func categories(fid: Int) async throws -> [BoardCategory] {
        guard fid > 0 else { throw NetworkError.invalidURL("fid=\(fid)") }
        let request = try client.request(path: "forumdisplay.php?fid=\(fid)")
        let html = try await client.sendText(request)
        return try BoardFilterParser.categories(html: html)
    }

    func threads(fid: Int, page: Int) async throws -> ThreadListPage {        guard fid > 0 else { throw NetworkError.invalidURL("fid=\(fid)") }
        let path = page > 1 ? "forumdisplay.php?fid=\(fid)&page=\(page)"
                            : "forumdisplay.php?fid=\(fid)"
        return try await threads(pageURL: path)
    }

    func threads(pageURL: String) async throws -> ThreadListPage {
        guard HTTPClient.isAllowedForumPath(pageURL) else {
            throw NetworkError.invalidURL("拒绝非站内分页 URL: \(pageURL)")
        }
        let request = try client.request(path: pageURL)
        let html = try await client.sendText(request)
        return try ThreadListParser.parse(html: html)
    }

    func posts(tid: Int, page: Int) async throws -> ThreadPage {
        guard tid > 0 else { throw NetworkError.invalidURL("tid=\(tid)") }
        let path = page > 1 ? "viewthread.php?tid=\(tid)&page=\(page)"
                            : "viewthread.php?tid=\(tid)"
        return try await posts(pageURL: path)
    }

    func posts(pageURL: String) async throws -> ThreadPage {
        guard HTTPClient.isAllowedForumPath(pageURL) else {
            throw NetworkError.invalidURL("拒绝非站内分页 URL: \(pageURL)")
        }
        let request = try client.request(path: pageURL)
        let html = try await client.sendText(request)
        return try ThreadDetailParser.parse(html: html)
    }
}
