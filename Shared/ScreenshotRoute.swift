import SwiftUI
import SwiftData

/// 截图路由：仅 `-DemoMode` 生效，供 Codemagic 一次 CI 跑完全部模块界面。
///
/// 用法：启动参数 `-DemoScreen=<raw>` 直接渲染对应界面，
/// 脚本不再需要 XCUI 逐级点击（点击路径易受动画/时序影响，是此前截图缺失的主因）。
enum ScreenshotScreen: String, CaseIterable {
    case home                // 首页（板块主题流）
    case thread              // 帖子详情（首帖 + 回复楼层 + 分页条）
    case threadReplies       // 帖子回复楼层（滚到页尾：回复流 + 分页条）
    case reply               // 回复框 Sheet
    case userCard            // 用户卡片 Sheet
    case imageViewer         // 图片全屏预览（多图画廊）
    case search              // 搜索结果
    case newPost             // 发帖页
    case boardManage         // 板块管理（置顶/收藏与排序）
    case chat                // 私信会话
    case message             // 消息（站内短信 / 系统消息）
    case profile             // 我的
    case savedThreads        // 我的收藏（本地书签）
    case blockedUsers        // 黑名单（本地屏蔽）
    case settings            // 设置
    case security            // 账号与安全
    case login               // 登录页
}

enum ScreenshotRoute {
    /// 从启动参数解析目标界面；未指定时返回 nil（走默认 3 Tab 画廊）。
    static var current: ScreenshotScreen? {
        for arg in ProcessInfo.processInfo.arguments where arg.hasPrefix("-DemoScreen=") {
            let raw = arg.replacingOccurrences(of: "-DemoScreen=", with: "")
            return ScreenshotScreen(rawValue: raw)
        }
        return nil
    }
}

/// 按 `ScreenshotScreen` 渲染单个界面。Tab 类界面带真实 TabBar，push 类界面带导航栏。
struct ScreenshotRouteView: View {
    let screen: ScreenshotScreen

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme

    /// 消息未读角标：与正式版同一口径（由 `MessageViewModel` 读收件箱后写入），
    /// 这里不再写死 `.badge(3)`。
    @ObservedObject private var unread = UnreadBadge.shared

    /// Tab 类界面的初始选中项，保证截图落在目标 Tab 上。
    @State private var tab: Int
    /// Sheet 类界面（回复框 / 用户卡）在出现后自动弹出。
    @State private var showReply = false
    @State private var showUserCard = false

    init(screen: ScreenshotScreen) {
        self.screen = screen
        _tab = State(initialValue: screen.tabIndex)
    }

    var body: some View {
        content
            .tint(Color.appPrimary(scheme))
            .preferredColorScheme(DemoMode.isDark ? .dark : nil)
            .environmentObject(SessionManager.shared)
            .task {
                await DemoData.seed(context: context)
                await SessionManager.shared.enterDemoSession()
                // Sheet 类界面：等首屏渲染完成后再弹，避免与入场动画冲突。
                if screen == .reply || screen == .userCard {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    showReply = (screen == .reply)
                    showUserCard = (screen == .userCard)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .home:
            tabHost
        case .message:
            tabHost
        case .profile:
            tabHost
        case .thread:
            NavigationStack {
                ThreadDetailView(thread: DemoData.sampleThread, forumID: 2)
            }
            .background(Color.appBackground(scheme))
        case .threadReplies:
            NavigationStack {
                ThreadDetailView(thread: DemoData.sampleThread, forumID: 2, jumpToLastReply: true)
            }
            .background(Color.appBackground(scheme))
        case .reply:
            NavigationStack {
                ThreadDetailView(thread: DemoData.sampleThread, forumID: 2)
            }
            .sheet(isPresented: $showReply) {
                ReplySheet(tid: DemoData.sampleThread.id) { _ in }
            }
        case .userCard:
            tabHost
                .sheet(isPresented: $showUserCard) {
                    UserCardSheet(userID: 1024, fallbackName: "老橡树")
                }
        case .imageViewer:
            // 多图画廊：顶部会显示「1 / 3」页码，左右可滑（Demo 用占位图，不依赖真实网络图源）。
            ImageViewer(urls: [
                URL(string: "https://placehold.co/1200x800/534AB7/FFFFFF/png?text=4D4Y+1")!,
                URL(string: "https://placehold.co/1200x800/8F86E8/FFFFFF/png?text=4D4Y+2")!,
                URL(string: "https://placehold.co/1200x800/2E2A5C/FFFFFF/png?text=4D4Y+3")!
            ], startIndex: 0)
        case .search:
            NavigationStack { SearchResultsView() }
        case .newPost:
            NewPostView()
        case .boardManage:
            NavigationStack { BoardManageView() }
        case .chat:
            NavigationStack { MessageChatView(userID: 1024, userName: "老橡树") }
        case .savedThreads:
            NavigationStack { SavedThreadsView() }
        case .blockedUsers:
            NavigationStack { BlockedUsersView() }
        case .settings:
            NavigationStack { SettingsView() }
        case .security:
            NavigationStack { AccountSecurityView() }
        case .login:
            LoginGateView(onSkip: {})
        }
    }

    /// 一级导航固定 3 个 Tab（首页 / 消息 / 我的），与正式发布一致。
    private var tabHost: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }
                .tag(0)

            MessageView()
                .tabItem { Label("消息", systemImage: "bell") }
                .badge(unread.privateMessages)
                .tag(1)

            ProfileView()
                .tabItem { Label("我的", systemImage: "person") }
                .tag(2)
        }
    }
}

private extension ScreenshotScreen {
    /// 该界面对应的 Tab 下标（非 Tab 界面返回 0，仅用于初始化）。
    var tabIndex: Int {
        switch self {
        case .message: return 1
        case .profile, .userCard: return 2
        default: return 0
        }
    }
}
