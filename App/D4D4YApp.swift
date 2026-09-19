import SwiftUI
import SwiftData

@main
struct D4D4YApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: PinnedForum.self,
                BlockedUser.self,
                ReadHistory.self,
                VisitedForum.self,
                LocalSettings.self,
                ThreadMediaCache.self
            )
        } catch {
            fatalError("SwiftData 容器初始化失败: \(error)")
        }
    }

    /// 截图用：仅渲染登录页（不进 Tab），便于单独验收登录模块视觉。
    private static let demoLoginArgument = "-DemoLogin"

    var body: some Scene {
        WindowGroup {
            if DemoMode.isOn {
                // 截图模式：用真实组件 + 离线样例数据呈现目标界面。
                Group {
                    if let screen = ScreenshotRoute.current {
                        // 一次 CI 跑完所有模块：`-DemoScreen=<name>` 直接渲染该界面。
                        ScreenshotRouteView(screen: screen)
                    } else if ProcessInfo.processInfo.arguments.contains(Self.demoLoginArgument) {
                        LoginGateView(onSkip: {})
                    } else {
                        ScreenshotGalleryView()
                    }
                }
                .modelContainer(modelContainer)
                .environmentObject(SessionManager.shared)
            } else {
                RootView()
                    .modelContainer(modelContainer)
                    .environmentObject(SessionManager.shared)
            }
        }
    }
}

/// 应用根：会话门禁 + 三 Tab 导航 + 明暗主题切换。
///
/// 启动流程：恢复 Keychain 凭据 → 已登录进 Tab；未登录进全屏登录页（可跳过为游客）。
/// 登录态由 `SessionManager` 单点发布，运行期掉线会自动回到登录页。
struct RootView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: SessionManager
    @Query private var settings: [LocalSettings]

    /// 恢复流程是否已完成（避免首帧就闪一下登录页）。
    @State private var hasRestored = false
    /// 用户主动选择"先以游客身份浏览"。
    @State private var skipLogin = false

    /// 主题模式：依据本地设置决定 preferredColorScheme。
    private var preferredScheme: ColorScheme? {
        guard let mode = settings.first?.themeMode else { return nil }
        switch mode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil   // system：跟随系统
        }
    }

    var body: some View {
        content
            .tint(Color.appPrimary(preferredScheme ?? .light))
            .preferredColorScheme(preferredScheme)
            .task {
                ensureDefaultSettings()
                session.restore()
                hasRestored = true
            }
    }

    @ViewBuilder
    private var content: some View {
        if !hasRestored {
            // 恢复凭据期间的占位（1 帧级别，避免登录页闪烁）。
            Color.appBackground(preferredScheme ?? .light)
                .ignoresSafeArea()
                .overlay { ProgressView() }
        } else if session.state.isAuthenticated || skipLogin {
            mainTabs
        } else {
            LoginGateView { skipLogin = true }
        }
    }

    /// 一级导航固定三个入口：首页 / 消息 / 我的。
    private var mainTabs: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }

            MessageView()
                .tabItem { Label("消息", systemImage: "bell") }
                .badge(3)

            ProfileView()
                .tabItem { Label("我的", systemImage: "person") }
        }
    }

    /// 首次启动写入默认设置（仅一条 singleton），保证主题切换有初始值。
    private func ensureDefaultSettings() {
        guard settings.isEmpty else { return }
        context.insert(LocalSettings())
        try? context.save()
    }
}
