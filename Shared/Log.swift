import Foundation
import os

/// 统一日志出口。Debug 模式下：
/// - os.Logger 分类输出（network / parser）
/// - 原始 HTML 自动落盘到 tmp/4d4y-debug/，便于分析真实 DOM 片段
enum Log {
    private static let subsystem = "com.d4d4y.client"

    static let network = Logger(subsystem: subsystem, category: "network")
    static let parser = Logger(subsystem: subsystem, category: "parser")

    /// Debug 构建下把响应体保存为本地 HTML 文件，返回保存路径（Release 为空操作）。
    @discardableResult
    static func dumpHTMLIfNeeded(_ data: Data, url: URL) -> URL? {
        #if DEBUG
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("4d4y-debug", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var name = url.absoluteString
            .replacingOccurrences(of: Self.baseURL, with: "")
            .replacingOccurrences(of: "https://", with: "")
        let invalid = CharacterSet(charactersIn: "/\\?%*:\"<>|&=")
        name = name.components(separatedBy: invalid).joined(separator: "_")
        if name.count > 80 { name = String(name.suffix(80)) }
        let file = dir.appendingPathComponent(name + ".html")
        try? data.write(to: file)
        Log.network.debug("HTML 已保存: \(file.path, privacy: .public)")
        return file
        #else
        return nil
        #endif
    }

    private static let baseURL = "https://www.4d4y.com/forum/"
}
