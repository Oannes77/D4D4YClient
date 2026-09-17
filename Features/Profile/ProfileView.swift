import SwiftUI
import SwiftData

/// 「我的」Tab。依据 `AuthenticationState` 在游客 / 登录态间切换，
/// 提供登录入口与退出登录；发帖/回复/收藏/消息不在本阶段范围。
struct ProfileView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: SessionManager
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showLoginSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    switch session.state {
                    case .guest:
                        HStack {
                            Text("当前状态")
                            Spacer()
                            Text("游客模式")
                                .foregroundStyle(Color.appTextSecondary(scheme))
                        }
                        Button {
                            showLoginSheet = true
                        } label: {
                            Label("登录", systemImage: "person.crop.circle.badge.plus")
                        }

                    case .authenticating:
                        HStack {
                            Text("当前状态")
                            Spacer()
                            ProgressView()
                        }

                    case .authenticated(let s):
                        HStack {
                            Text("当前状态")
                            Spacer()
                            Text("已登录")
                                .foregroundStyle(Color.appTextSecondary(scheme))
                        }
                        HStack {
                            Text("用户名")
                            Spacer()
                            Text(s.username)
                                .foregroundStyle(Color.appTextSecondary(scheme))
                        }
                        Button(role: .destructive) {
                            session.logout()
                        } label: {
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        }

                    case .failed(let error):
                        HStack {
                            Text("当前状态")
                            Spacer()
                            Text("登录失败")
                                .foregroundStyle(Color.appError(scheme))
                        }
                        Text(error.errorDescription ?? "登录失败")
                            .font(.caption)
                            .foregroundStyle(Color.appError(scheme))
                        Button {
                            showLoginSheet = true
                        } label: {
                            Label("重试登录", systemImage: "arrow.clockwise")
                        }
                    }

                    Text("登录后获得更多功能（发帖、回复、收藏、消息等将在后续阶段提供）")
                        .font(.caption)
                        .foregroundStyle(Color.appTextTertiary(scheme))
                } header: { Text("账户") }

                Section("阅读设置") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Text("主题 / 字号 / 行距 / 密度")
                    }
                }

                Section("本地数据") {
                    NavigationLink {
                        Text("屏蔽作者管理将在后续 Sprint 接入")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextTertiary(scheme))
                            .padding()
                    } label: { Text("屏蔽作者") }

                    Button("清理缓存", role: .destructive) {
                        viewModel.clearCache()
                    }
                }

                Section {
                    Text("D4D4Y 第三方阅读客户端 · 仅解析公开页面，不绕过任何权限")
                        .font(.caption2)
                        .foregroundStyle(Color.appTextTertiary(scheme))
                } header: { Text("关于") }
            }
            .navigationTitle("我的")
            .scrollContentBackground(.hidden)
            .background(Color.appBackground(scheme))
            .alert("缓存", isPresented: $viewModel.showClearResult) {
                Button("好", role: .cancel) {}
            } message: {
                Text(viewModel.clearResultMessage ?? "")
            }
            .sheet(isPresented: $showLoginSheet) {
                LoginView()
            }
        }
    }
}
