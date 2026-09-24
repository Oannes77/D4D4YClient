import Foundation

/// 截图路由专用的一次性状态覆盖（**只在 `-DemoMode` 下生效**）。
///
/// 为什么需要它：有些界面状态在演示里走不到 —— 演示会话是「已登录」的、也不联网，
/// 所以「站点登录门」（游客被挡）永远不会自然出现。这里由截图路由注入，
/// 但**取值必须来自真实夹具的解析结果**（见 `DemoData.loadLoginGateNotice()`），
/// 不许手写文案，否则截图验收的就是一段我们编的话。
///
/// 用一个 `ObservableObject` 而不是全局 `static var`：路由在 `.task` 里赋值，
/// 需要 SwiftUI 收到通知重新渲染，静态变量不会触发刷新。
final class DemoOverrides: ObservableObject {
    static let shared = DemoOverrides()

    /// 首页要展示的站点提示（登录门）。nil = 按 `HomeViewModel` 的真实状态渲染。
    @Published var homeNotice: SiteNotice?

    private init() {}
}
