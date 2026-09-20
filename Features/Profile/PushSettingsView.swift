import SwiftUI

/// 消息推送设置（我的 → 消息推送）。
///
/// 这里设置的是**后台刷新间隔**：iOS 在后台唤起 App 拉一次收件箱，
/// 把真实未读数写到消息 Tab 的角标上（与前台同一口径，读不到就是 0，不写死数字）。
///
/// 页面如实交代两件事，不让人误以为「秒级推送」：
/// 1. 实际唤起时机由 iOS 决定（电量 / 使用习惯 / 低电量模式都会影响），只能保证按间隔尝试；
/// 2. 收件箱需要登录态，未登录时后台刷新读不到任何数据（也就不会伪造未读数）。
struct PushSettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var prefs = PreferenceStore.shared

    @State private var isLoggedIn = false

    var body: some View {
        List {
            Section {
                ForEach(PreferenceStore.pushOptions) { option in
                    Button {
                        prefs.pushFrequencyMinutes = option.minutes
                    } label: {
                        HStack {
                            Text(option.label)
                                .foregroundStyle(Color.appTextPrimary(scheme))
                            Spacer()
                            if prefs.pushFrequencyMinutes == option.minutes {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.appPrimary(scheme))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("检查未读消息的间隔")
            } footer: {
                Text("间隔越短越及时，也更耗电。设置为「关闭」后不再在后台刷新。")
            }

            Section {
                statusRow(title: "当前设置", value: prefs.pushLabel)
                statusRow(title: "上次检查",
                          value: prefs.lastPushCheckAt.map { RelativeDateText.friendly($0) } ?? "尚未检查过")
                statusRow(title: "账号", value: isLoggedIn ? "已登录" : "未登录")
            } header: {
                Text("状态")
            }

            Section {
                note("系统会在后台唤醒 App 拉取未读消息并更新角标；实际时机由 iOS 决定，不保证准时，也不保证每次都能唤醒。")
                note("收件箱需要登录才能读取，未登录时后台刷新不会得到任何数据，角标也不会显示数字。")
                note("角标数字只来自论坛真实返回的未读标记，读不到就是 0 —— 客户端不编造未读数。")
                if !BackgroundRefresh.isConfigured {
                    note("当前构建未包含后台任务配置（Info.plist 缺少 BGTaskSchedulerPermittedIdentifiers），后台刷新不会生效。")
                }
            } header: {
                Text("说明")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground(scheme))
        .navigationTitle("消息推送")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoggedIn = SessionManager.shared.state.isAuthenticated
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.appTextPrimary(scheme))
            Spacer()
            Text(value).foregroundStyle(Color.appTextTertiary(scheme))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.appTextSecondary(scheme))
    }
}
