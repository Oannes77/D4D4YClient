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
    @Query private var settings: [LocalSettings]
    @State private var showLoginSheet = false

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
        DemoMode.isOn ? "论坛元老 · UID \(uid)" : "UID \(uid)"
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
            .alert("缓存", isPresented: $viewModel.showClearResult) {
                Button("好", role: .cancel) {}
            } message: {
                Text(viewModel.clearResultMessage ?? "")
            }
        }
    }

    // MARK: - 个人信息资料框
    private var profileHeader: some View {
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
        }
        .padding(16)
        .background(Color.appSurface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 我的宫格
    private var myGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
            ForEach(myItems) { item in
                Button { } label: {
                    VStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.title2)
                            .foregroundStyle(Color.appPrimary(scheme))
                        Text(item.title)
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary(scheme))
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                }
            }
        }
        .background(Color.appSurface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var myItems: [MyItem] {
        [
            MyItem(icon: "doc.text", title: "帖子"),
            MyItem(icon: "bubble.left", title: "回复"),
            MyItem(icon: "star", title: "收藏"),
            MyItem(icon: "person.2", title: "好友"),
            MyItem(icon: "person.crop.circle.badge.checkmark", title: "关注"),
            MyItem(icon: "person.crop.circle.badge.xmark", title: "黑名单")
        ]
    }

    // MARK: - 设置框
    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingRow(icon: "paintbrush", title: "主题外观", value: themeText)
            settingRow(icon: "text.bubble", title: "回帖占位符", value: "Peace&Love")
            settingRow(icon: "eye", title: "显示帖子正文", value: "开")
            settingRow(icon: "list.bullet.rectangle", title: "版块管理")
            settingRow(icon: "bell.badge", title: "消息推送", value: "15 分钟")
            settingRow(icon: "lock.shield", title: "账号与安全")
        }
        .background(Color.appSurface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
        .background(Color.appSurface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 通用设置行
    @ViewBuilder
    private func settingRow(icon: String, title: String, value: String? = nil) -> some View {
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

        Divider()
            .padding(.leading, 50)
            .background(Color.appDivider(scheme))
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
private struct MyItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
}
