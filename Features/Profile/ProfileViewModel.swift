import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var showClearResult = false
    @Published var clearResultMessage: String?

    /// 清理本地调试 HTML 缓存目录（Phase 1.5 Log.dumpHTMLIfNeeded 落盘处）。
    /// 仅删除 App 自身 tmp 目录，不涉及任何服务器数据。
    func clearCache() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("4d4y-debug", isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            clearResultMessage = "没有可清理的缓存"
            showClearResult = true
            return
        }
        do {
            try FileManager.default.removeItem(at: dir)
            clearResultMessage = "已清理本地缓存"
        } catch {
            clearResultMessage = "清理失败：\(error.localizedDescription)"
        }
        showClearResult = true
    }
}
