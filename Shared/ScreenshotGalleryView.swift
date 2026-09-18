import SwiftUI
import SwiftData

/// 仅 `-DemoMode` 下作为应用根视图：用真实组件 + 离线样例数据，呈现与正式发布完全一致
/// 的 **3 个 Tab（首页 / 消息 / 我的）**，供 Codemagic 截图验证设计令牌。
///
/// 帖子详情 / 回复框 不是 Tab，而是「首页点帖子进入详情」「详情点回复弹出 Sheet」的真实交互路径，
/// 由 `AppScreenshotTests` 通过 XCUI 点按到达后截图——与上午 HTML 原型（v3.0）的 tabbar 结构一致。
///
/// 不改动任何正常发布路径；仅当启动参数含 `-DemoMode` 时由 `D4D4YApp` 选用。
struct ScreenshotGalleryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }

            MessageView()
                .tabItem { Label("消息", systemImage: "bell") }
                .badge(3)

            ProfileView()
                .tabItem { Label("我的", systemImage: "person") }
        }
        .tint(Color.appPrimary(scheme))
        .preferredColorScheme(DemoMode.isDark ? .dark : nil)
        .environmentObject(SessionManager.shared)
        .task {
            await DemoData.seed(context: context)
            await SessionManager.shared.enterDemoSession()
        }
    }
}
