import Foundation

/// HTTP method。当前 PoC 只用 GET，POST 为登录阶段预留。
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

/// 一次 HTTP 请求的完整描述。
/// 预留 body / 自定义 Header，登录 Discuz! 时直接复用。
struct HTTPRequest {
    var method: HTTPMethod = .get
    var url: URL
    var headers: [String: String] = [:]
    var body: Data?
    /// nil 表示使用 client 默认超时
    var timeoutInterval: TimeInterval? = nil

    init(method: HTTPMethod = .get, url: URL,
         headers: [String: String] = [:], body: Data? = nil,
         timeoutInterval: TimeInterval? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeoutInterval = timeoutInterval
    }

    static func get(_ url: URL, headers: [String: String] = [:]) -> HTTPRequest {
        HTTPRequest(method: .get, url: url, headers: headers)
    }
}

/// 网络与解析前的所有失败形态，Debug 模式下逐类区分。
enum NetworkError: Error, LocalizedError {
    case invalidURL(String)
    case transport(URLError)
    case httpStatus(code: Int, url: URL)
    case emptyBody(URL)
    case textEncodingFailed(URL)
    /// 站点返回 Cloudflare 质询页（"Just a moment..."），未绕过、直接失败并提示用户。
    case cloudflareChallenge(URL)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let s):            return "无效 URL: \(s)"
        case .transport(let e):             return "网络请求失败: \(e.localizedDescription)"
        case .httpStatus(let code, _):      return "HTTP 状态码异常: \(code)"
        case .emptyBody:                    return "HTML 为空"
        case .textEncodingFailed:           return "HTML 编码解码失败"
        case .cloudflareChallenge:          return "站点返回了 Cloudflare 人机验证页（未绕过）"
        }
    }
}

/// 全站唯一网络出口。后续登录（POST / Cookie / Session）继续复用本类。
final class HTTPClient {

    static let baseURL = URL(string: "https://www.4d4y.com/forum/")!

    /// 站内绝对地址（系统分享 / 浏览器打开用）：由相对路径现算，永远指向论坛本站。
    /// 例：`absoluteURL(path: "viewthread.php?tid=193033")`。
    static func absoluteURL(path: String) -> URL? {
        URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    /// 模拟移动 Safari（**全局默认**）。
    ///
    /// ⚠️ **此站按 User-Agent 分发模板**，不是「对 UA 无限制」：
    /// 命中移动 UA → 精简的 `templates/wap/`；否则 → 完整 PC 模板。
    /// 客户端与**全部解析器、`Tests/Fixtures` 夹具**都建立在 WAP 模板之上，
    /// 所以这里必须保持移动 UA —— 改成 PC 等于换掉所有页面结构（见 `docs/SiteFacts.md`）。
    private static let defaultHeaders: [String: String] = [
        "User-Agent": mobileUserAgent,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9",
    ]

    /// 全局默认：移动 Safari。
    static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// 桌面 Safari UA —— **只给「WAP 模板拿不到的信息」用**，别当全局默认。
    ///
    /// 唯一已知用途：首图元数据检测（`ImageMetadataRepository`）。
    /// 附件图在 WAP 模板里**完全不渲染**（页面尾部虽有 `attachimgshow(pid)` 调用，
    /// 但它要找的 `#aimg_<aid>` 元素根本不存在，属空转）；PC 模板才有
    /// `<img id="aimg_<aid>" file="https://img02.4d4y.com/forum/attachments/...">`，
    /// 而该地址游客可直接取到（实测 200 image/*，不需登录、不需 Referer）。
    static let desktopUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

    /// 需要 PC 模板时用的请求头（配合 `request(path:headers:)` 单次覆盖）。
    static let desktopHeaders: [String: String] = [
        "User-Agent": desktopUserAgent,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9",
    ]

    private let session: URLSession
    private let defaultTimeout: TimeInterval

    /// - Parameter session: 注入点。Cookie 存储由 URLSessionConfiguration 决定，
    ///   登录后只需保证使用同一 configuration（HTTPCookieStorage.shared）即可保持会话。
    init(session: URLSession? = nil, timeout: TimeInterval = 20) {
        self.defaultTimeout = timeout
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = HTTPCookieStorage.shared   // 预留 Cookie 会话
            config.timeoutIntervalForRequest = timeout
            config.timeoutIntervalForResource = timeout * 2
            self.session = URLSession(configuration: config)
        }
    }

    /// 以相对路径（相对 https://www.4d4y.com/forum/）构造请求。
    func request(path: String, headers: [String: String] = [:]) throws -> HTTPRequest {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else {
            throw NetworkError.invalidURL(path)
        }
        var merged = Self.defaultHeaders
        merged.merge(headers) { _, new in new }
        return HTTPRequest(method: .get, url: url.absoluteURL, headers: merged)
    }

    /// 发送请求，返回原始 Data。状态码 / 网络 / 空响应在此统一拦截。
    func send(_ request: HTTPRequest) async throws -> Data {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeoutInterval ?? defaultTimeout
        request.headers.forEach { urlRequest.setValue($1, forHTTPHeaderField: $0) }

        Log.network.debug("\(request.method.rawValue) \(request.url.absoluteString, privacy: .public)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let e as URLError {
            Log.network.error("传输失败: \(e.code.rawValue) \(e.localizedDescription, privacy: .public)")
            throw NetworkError.transport(e)
        } catch {
            throw NetworkError.transport(URLError(.unknown))
        }

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.httpStatus(code: -1, url: request.url)
        }

        // 1) Cloudflare 质询页：必须根据响应正文内容特征识别（而非单纯状态码），
        //    且在状态码判断之前——质询页常返回 HTTP 403，否则会被误判为普通 403。
        //    不绕过、不交互；只识别并失败。只有正文同时含质询特征才判定为 CF。
        if !data.isEmpty, Self.looksLikeCloudflareChallenge(data) {
            Log.network.fault("命中 Cloudflare 质询页，放弃处理（不绕过）")
            throw NetworkError.cloudflareChallenge(request.url)
        }

        // 2) 普通 HTTP 状态码。非 2xx 一律按状态码异常（含真正的 403/404/5xx）。
        guard (200..<300).contains(http.statusCode) else {
            Log.network.error("HTTP \(http.statusCode) \(request.url.absoluteString, privacy: .public)")
            throw NetworkError.httpStatus(code: http.statusCode, url: request.url)
        }

        // 3) 空响应
        guard !data.isEmpty else {
            throw NetworkError.emptyBody(request.url)
        }

        Log.dumpHTMLIfNeeded(data, url: request.url)   // Debug 环境保存原始 HTML
        return data
    }

    /// 发送请求并把响应体按正确编码解码为 String（解码逻辑见 Shared/HTMLDecoder）。
    /// 站点声明 charset=gbk，用 GB18030（GBK 超集）解码，避免生僻字丢失。
    func sendText(_ request: HTTPRequest) async throws -> String {
        let data = try await send(request)
        guard let text = HTMLDecoder.decode(data) else {
            throw NetworkError.textEncodingFailed(request.url)
        }

        // 统一掉线检测：任意页面出现「您还未登录」即说明服务端不再认可当前 Cookie。
        // 此处只发通知、不直接改状态；由 SessionManager 判定是否真需要作废会话
        // （登录流程本身也会命中该文案，但当时并非已登录态，会被安全忽略）。
        if text.contains("您还未登录") {
            NotificationCenter.default.post(name: .d4d4ySessionExpired, object: nil)
        }

        return text
    }

    /// Cloudflare 质询页特征检测（只识别，不交互、不绕过）。
    static func looksLikeCloudflareChallenge(_ data: Data) -> Bool {
        guard let s = String(data: data.prefix(8192), encoding: .utf8) else { return false }
        return s.contains("Just a moment...") && s.contains("challenges.cloudflare.com")
    }

    /// 仅允许同一论坛站点的相对分页 URL（https://www.4d4y.com/forum/ 之下）。
    /// 拒绝绝对 URL、跨域、以及逃逸到 base 之外的路径，避免引入任意外部 URL 请求能力。
    /// PaginationParser 解析出的 previousPageURL / nextPageURL 必须经过此校验后才可请求。
    static func isAllowedForumPath(_ path: String) -> Bool {
        guard let resolved = URL(string: path, relativeTo: Self.baseURL)?.absoluteURL else { return false }
        guard resolved.scheme == "https" else { return false }
        guard resolved.host == Self.baseURL.host else { return false }
        guard resolved.path.hasPrefix(Self.baseURL.path) else { return false }
        return true
    }
}
