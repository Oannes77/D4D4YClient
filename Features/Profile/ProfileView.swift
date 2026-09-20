import SwiftUI
import SwiftData

/// 「我的」Tab（Threads v2.3 风格）。
///
/// 结构：
/// 1. 个人信息资料框（头像 + 用户名 + 分组 / UID）。
/// 2. 「我的」宫格：帖子 / 回复 / 收藏 / 好友 / 关注 / 黑名单。
/// 3. 设置框：主题外观 / 回帖占位符 / 显示帖子正文 / 版块管理 / 消息推送 / 账号与安全 / 关于。
struct ProfileView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: SessionManager
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ProfileViewModel()
    /// 客户端偏好（占位符 / 是否显示正文 / 后台刷新间隔）：设置框里显示的就是它里面的真实值。
    @ObservedObject private var prefs = PreferenceStore.shared
    @Query private var settings: [LocalSettings]
    @State private var showLoginSheet = false
    @State private var showAccountSecurity = false

    /// 是否已登录（决定「账号与安全」是进账号页还是唤起登录）。
    /// 演示/截图模式视为已登录，避免出现"点击登录"箭头破坏截图。
    private var isLoggedIn: Bool { session.state.isAuthenticated || DemoMode.isOn }

    /// 演示/真实模式下统一取当前用户名；未登录时显示提示。
    private var username: String {
        if case .authenticated(let s) = session.state { return s.username }
        if DemoMode.isOn { return "演示用户" }
        return "未登录"
    }

    private var uid: Int {
        if case .authenticated(let s) = session.state { return s.uid }
        return 1
    }

    private var groupText: String {
        if !isLoggedIn { return "点击登录 4D4Y 账号" }
        return DemoMode.isOn ? "论坛元老 · UID \(uid)" : "UID \(uid)"
    }

    private var themeText: String {
        switch settings.first?.themeMode ?? "system" {
        case "light": return "浅色"
        case "dark":  return "深色"
        default:      return "跟随系统"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileHeader
                    myGrid
                    settingsCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.appBackground(scheme))
            .scrollContentBackground(.hidden)
            .navigationTitle("我的")
            .sheet(isPresented: $showLoginSheet) {
                LoginView()
            }
            .sheet(isPresented: $showAccountSecurity) {
                AccountSecurityView()
            }
            .alert("缓存", isPresented: $viewModel.showClearResult) {
                Button("好", role: .cancel) {}
            } message: {
                Text(viewModel.clearResultMessage ?? "")
            }
        }
    }

    // MARK: - 个人信息资料框
    private var profileHeader: some View {
        Button {
            // 未登录时点击资料框即唤起登录。
            if !isLoggedIn { showLoginSheet = true }
        } label: {
            HStack(spacing: 16) {
                AvatarView(authorID: uid, authorName: username, size: 72)
                    .overlay(
                        Circle()
                            .stroke(Color.appDivider(scheme), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(username)
                        .font(.title3).fontWeight(.bold)
                        .foregroundStyle(Color.appTextPrimary(scheme))

                    Text(groupText)
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary(scheme))
                }

                Spacer()

                if !isLoggedIn {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.appTextTertiary(scheme))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(16)
        .appCard(scheme)
    }

    // MARK: - 我的宫格
    /// 六个入口全部可点、且都指向真实内容：收藏 / 黑名单走本地 SwiftData，
    /// 帖子 / 回复 / 好友 / 关注走论坛「我的中心」—— 不再有点了没反应的死按钮。
    private var myGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
            ForEach(MyFeature.allCases) { feature in
                NavigationLink {
                    destination(for: feature)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: feature.icon)
                            .font(.title2)
                            .foregroundStyle(Color.appPrimary(scheme))
                        Text(feature.title)
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary(scheme))
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(.plain)
            }
        }
        .appCard(scheme)
    }

    /// 宫格目标页。六个入口全部接真实内容：
    /// - 收藏 / 黑名单 = 本地 SwiftData 列表（点进去就是真实数据）；
    /// - 帖子 / 回复 / 好友 / 关注 = 论坛「我的中心」（`my.php`）真实列表，
    ///   未登录时给登录入口，站点没有该栏目时如实说明并给网页版出口，绝不显示假列表。
    @ViewBuilder
    private func destination(for feature: MyFeature) -> some View {
        switch feature {
        case .saved:   SavedThreadsView()
        case .blocked: BlockedUsersView()
        case .threads: MySpaceListView(kind: .threads)
        case .posts:   MySpaceListView(kind: .replies)
        case .friends: MySpaceListView(kind: .friends)
        case .follows: MySpaceListView(kind: .follows)
        }
    }

    // MARK: - 设置框
    /// 六行设置**全部可点且真的生效**（右侧数值取真实来源，不再是硬编码）：
    /// 主题外观 → 阅读设置；回帖占位符 → 可编辑（回复/发帖立即用新值）；
    /// 显示帖子正文 → 开关，直接决定列表是否显示正文预览；
    /// 版块管理 → 真实排序页；消息推送 → 间隔设置 + 真实后台刷新；账号与安全 → 已接。
    private var settingsCard: some View {
        VStack(spacing: 0) {
            navRow(icon: "paintbrush", title: "主题外观", value: themeText) {
                SettingsView()
            }
            navRow(icon: "text.bubble", title: "回帖占位符", value: prefs.replyPlaceholder) {
                ReplyPlaceholderView()
            }
            toggleRow(icon: "eye", title: "显示帖子正文", isOn: $prefs.showPostContent)
            navRow(icon: "list.bullet.rectangle", title: "版块管理", value: nil) {
                BoardManageView()
            }
            navRow(icon: "bell.badge", title: "消息推送", value: prefs.pushLabel) {
                PushSettingsView()
            }
            actionRow(icon: "lock.shield",
                      title: "账号与安全",
                      value: isLoggedIn ? "已登录" : "未登录") {
                if isLoggedIn {
                    showAccountSecurity = true
                } else {
                    showLoginSheet = true
                }
            }
        }
        .appCard(scheme)
    }

    // MARK: - 关于框
    private var aboutCard: some View {
        VStack(spacing: 0) {
            Button {
                viewModel.clearCache()
            } label: {
                HStack {
                    settingLabel(icon: "trash", title: "清理缓存")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .foregroundStyle(Color.appTextPrimary(scheme))

            Divider().background(Color.appDivider(scheme))

            HStack {
                settingLabel(icon: "info.circle", title: "关于 4D4Y 与客户端作者")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .appCard(scheme)
    }

    // MARK: - 通用设置行
    /// 行外壳：内容 + 左侧缩进的 0.5px 分割线。
    private func rowShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
            Divider()
                .padding(.leading, 50)
                .background(Color.appDivider(scheme))
        }
    }

    /// 可跳转行：点击 push 到目标页面（右侧保留自己的 chevron，不用系统样式）。
    private func navRow<Destination: View>(icon: String, title: String,
                                           value: String? = nil,
                                           @ViewBuilder destination: () -> Destination) -> some View {
        rowShell {
            NavigationLink {
                destination()
            } label: {
                settingRowContent(icon: icon, title: title, value: value)
            }
            .buttonStyle(.plain)
        }
    }

    /// 开关行：就地切换，不需要进二级页面。
    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        rowShell {
            HStack {
                settingLabel(icon: icon, title: title)
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(Color.appPrimary(scheme))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    /// 动作行：整行可点，行为由调用方决定。
    private func actionRow(icon: String, title: String, value: String? = nil,
                           action: @escaping () -> Void) -> some View {
        rowShell {
            Button(action: action) {
                settingRowContent(icon: icon, title: title, value: value)
            }
            .buttonStyle(.plain)
        }
    }

    private func settingRowContent(icon: String, title: String, value: String?) -> some View {
        HStack {
            settingLabel(icon: icon, title: title)
            Spacer()
            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextTertiary(scheme))
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.appTextTertiary(scheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func settingLabel(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.appPrimary(scheme))
                .frame(width: 24, alignment: .center)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.appTextPrimary(scheme))
        }
    }
}

// MARK: - 宫格模型

/// 「我的」宫格的六个入口。
/// - `saved` / `blocked` 走本地数据（SwiftData），点进去就是真实列表；
/// - `threads` / `posts` / `friends` / `follows` 走论坛「我的中心」（`my.php`），
///   内容在服务器上、需要登录，界面按「登录门 / 无此栏目 / 结构未识别」分别如实呈现。
private enum MyFeature: String, CaseIterable, Identifiable {
    case threads, posts, saved, friends, follows, blocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .threads: return "帖子"
        case .posts:   return "回复"
        case .saved:   return "收藏"
        case .friends: return "好友"
        case .follows: return "关注"
        case .blocked: return "黑名单"
        }
    }

    var icon: String {
        switch self {
        case .threads: return "doc.text"
        case .posts:   return "bubble.left"
        case .saved:   return "star"
        case .friends: return "person.2"
        case .follows: return "person.crop.circle.badge.checkmark"
        case .blocked: return "person.crop.circle.badge.xmark"
        }
    }
}
