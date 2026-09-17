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

    var body: some Scene {
        WindowGroup {
            if DemoMode.isOn {
                // 截图模式：用真实组件 + 离线样例数据呈现 5 个目标界面。
                ScreenshotGalleryView()
                    .modelContainer(modelContainer)
            } else {
                RootView()
                    .modelContainer(modelContainer)
                    .environmentObject(SessionManager.shared)
            }
        }
    }
}

/// 应用根：三 Tab 导航 + 明暗主题切换。
/// 一级导航固定三个入口：首页 / 板块 / 我的。
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var settings: [LocalSettings]

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
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }

            ForumListView()
                .tabItem { Label("板块", systemImage: "square.stack.3d.up") }

            ProfileView()
                .tabItem { Label("我的", systemImage: "person") }
        }
        .tint(Color.appPrimary(preferredScheme ?? .light))
        .preferredColorScheme(preferredScheme)
        .task {
            ensureDefaultSettings()
            SessionManager.shared.restore()
        }
    }

    /// 首次启动写入默认设置（仅一条 singleton），保证主题切换有初始值。
    private func ensureDefaultSettings() {
        guard settings.isEmpty else { return }
        context.insert(LocalSettings())
        try? context.save()
    }
}
