import Foundation

// MARK: - ImageMetadataError
/// 图片检测错误：明确区分拦截 / 网络失败，绝不绕过 Cloudflare。
enum ImageMetadataError: LocalizedError {
    case pageUnavailable          // Cloudflare / 拦截页
    case network(String)          // 网络失败

    var errorDescription: String? {
        switch self {
        case .pageUnavailable: return "图片检测失败：站点返回拦截页（如 Cloudflare），请稍后在 App 内重试。"
        case .network(let s):  return "图片检测网络失败：\(s)"
        }
    }
}

// MARK: - ImageMetadataRepository
/// 媒体感知数据层（方案 B：延迟检测 + 缓存）。
///
/// 数据流：ForumThread(id: tid)
///   ↓ ImageMetadataRepository.detect(tid:)        // 请求 viewthread 第一页 + 解析
///   ↓ ThreadMediaInfo（纯数据：hasImage / previewImageURL / hasAttachment）
///   ↓ ThreadMediaCache（SwiftData 持久化，24h 有效）
///
/// 设计原则：
/// 1. 不修改 ForumThread 网络模型——媒体分析与网络模型严格分离；
/// 2. 公开帖图片无需登录即可检测（默认 HTTPClient 即可，不依赖会话 Cookie）；
/// 3. 遇到 Cloudflare / 拦截页立即失败，绝不绕过；
/// 4. 并发受限（默认 4 路），每个子任务自建 HTTPClient，避免跨 actor 捕获非 Sendable 实例。
final class ImageMetadataRepository {

    /// 单次列表检测上限：避免打开列表即请求几十个帖子（任务要求只检测当前列表优先主题）。
    static let cappedDetectCount = 20

    private let client: HTTPClient
    init(client: HTTPClient = HTTPClient()) { self.client = client }

    /// 检测单个主题的媒体信息：请求 viewthread 第一页 → 解析正文图片 + 附件。
    /// - Parameter tid: 主题 ID。
    func detect(tid: Int) async -> Result<ThreadMediaInfo, ImageMetadataError> {
        do {
            let req = try client.request(path: "viewthread.php?tid=\(tid)")
            let html = try await client.sendText(req)
            let urls = ThreadImageParser.parseContentImageURLs(from: html)
            let hasAttachment = ThreadImageParser.detectHasAttachment(from: html)
            let previewText = ThreadImageParser.parsePreviewText(from: html)
            let info = ThreadMediaInfo(
                tid: tid,
                hasImage: !urls.isEmpty,
                previewImageURL: urls.first,
                hasAttachment: hasAttachment,
                previewText: previewText
            )
            return .success(info)
        } catch let e as NetworkError {
            if case .cloudflareChallenge = e { return .failure(.pageUnavailable) }
            return .failure(.network(e.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    /// 并发受限批量检测（默认 4 路）。
    /// 仅用于当前列表优先显示的主题；调用方应自行跳过已缓存的 tid。
    /// - Parameters:
    ///   - tids: 待检测的主题 ID 列表（建议已去重、仅当前页可见主题）。
    ///   - maxConcurrent: 最大并发数（3~4）。
    /// - Returns: 成功检测到的 ThreadMediaInfo 数组（失败的主题被静默跳过）。
    static func detectAll(_ tids: [Int], maxConcurrent: Int = 4) async -> [ThreadMediaInfo] {
        guard !tids.isEmpty else { return [] }
        let batchSize = max(1, min(maxConcurrent, 6))
        var results: [ThreadMediaInfo] = []
        results.reserveCapacity(tids.count)

        for batch in tids.chunked(into: batchSize) {
            await withTaskGroup(of: ThreadMediaInfo?.self) { group in
                for tid in batch {
                    // 子任务内自建 HTTPClient，避免跨 actor 捕获非 Sendable 实例（严格并发安全）。
                    group.addTask {
                        let repo = ImageMetadataRepository()
                        switch await repo.detect(tid: tid) {
                        case .success(let info): return info
                        case .failure:           return nil
                        }
                    }
                }
                for await info in group where info != nil {
                    results.append(info!)
                }
            }
        }
        return results
    }
}

// MARK: - Array 分块辅助
private extension Array {
    /// 按指定大小切分为子数组。
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
