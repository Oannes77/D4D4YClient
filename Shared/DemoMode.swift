import Foundation

/// 截图/演示模式开关：仅用于 Codemagic 自动截图，不影响正常发布构建。
///
/// - `-DemoMode`：开启演示数据注入，并把根视图切换为 `ScreenshotGalleryView`。
/// - `-DarkMode`：在演示模式下强制深色主题截图。
enum DemoMode {
    static var isOn: Bool {
        ProcessInfo.processInfo.arguments.contains("-DemoMode")
    }

    static var isDark: Bool {
        ProcessInfo.processInfo.arguments.contains("-DarkMode")
    }
}
