import SwiftUI

/// 「我的」宫格 → 论坛「我的中心」（`my.php`）列表页。
///
/// 与「我的收藏」「黑名单」不同，这里的四栏（帖子 / 回复 / 好友 / 关注）**内容在服务器上**，
/// 必须登录才能读。因此页面刻意把四种结果分开呈现，任何一种都不含糊：
///
/// | 情况 | 界面 |
/// |------|------|
/// | 正常有内容 | 列表（帖子型点击进详情；用户型点击弹用户卡） |
/// | 页面正常但没内容 | 明确的空态文案（不编造条目） |
/// | 命中登录门 | 「需要登录」+ 登录入口 |
/// | 本站没有这个栏目 | 说明 + 网页版出口（如 Discuz! 7.2 没有「关注」） |
/// | 结构未识别 / 网络失败 | 原因 + 重试 |
struct MySpaceListView: View {
    let kind: MySpaceKind

    @Environment(\.colorScheme) private var scheme
    @State private var state: MySpaceLoadState = .idle
    @State private var showLogin = false
    @State private var selectedUser: MySpaceEntry?

    private let repository: MySpaceRepositoryProtocol

    init(kind: MySpaceKind, repository: MySpaceRepositoryProtocol = MySpaceRepository()) {
        self.kind = kind
        self.repository = repository
    }

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                loadingView
            case .loaded(let list):
                listView(list)
            case .empty:
                emptyView
            case .requiresLogin:
                loginView
            case .sectionMissing(let name):
                UnavailableFeatureView(title: kind.listTitle,
                                       message: messageForMissingSection(name),
                                       webPath: kind.webPath)
            case .failed(let message):
                failedView(message)
            }
        }
        .background(Color.appBackground(scheme))
        .navigationTitle(kind.listTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
        .sheet(isPresented: $showLogin) { LoginView() }
        .sheet(item: $selectedUser) { entry in
            if let uid = entry.userID {
                UserCardSheet(userID: uid, fallbackName: entry.userName ?? "")
            }
        }
    }

    // MARK: - 加载

    private func load() async {
        // 演示 / 截图模式：用离线样例，不联网、不碰鉴权。
        if DemoMode.isOn {
            apply(DemoData.mySpaceDemo(kind: kind))
            return
        }
        state = .loading
        apply(await repository.entries(kind: kind))
    }

    private func apply(_ result: Result<[MySpaceEntry], MySpaceError>) {
        switch result {
        case .success(let list):
            state = list.isEmpty ? .empty : .loaded(list)
        case .failure(let error):
            switch error {
            case .requiresLogin:             state = .requiresLogin
            case .sectionMissing(let name):  state = .sectionMissing(name)
            case .unsupported, .network:     state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - 列表

    private func listView(_ list: [MySpaceEntry]) -> some View {
        List {
            ForEach(list) { entry in
                if let tid = entry.threadID {
                    NavigationLink {
                        ThreadDetailView(tid: tid, title: entry.title)
                    } label: {
                        row(entry)
                    }
                } else {
                    Button {
                        selectedUser = entry
                    } label: {
                        row(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ entry: MySpaceEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let uid = entry.userID {
                AvatarView(authorID: uid, authorName: entry.userName ?? entry.title, size: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(Color.appTextPrimary(scheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .accessibilityIdentifier("my-space-row")

                if !entry.detail.isEmpty || !entry.timeRaw.isEmpty {
                    HStack(spacing: 6) {
                        if !entry.detail.isEmpty {
                            Text(entry.detail).lineLimit(1)
                        }
                        if !entry.timeRaw.isEmpty {
                            Text(entry.timeRaw)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(Color.appTextTertiary(scheme))
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 各种状态

    private var loadingView: some View {
        ProgressView("加载中…")
            .foregroundStyle(Color.appTextSecondary(scheme))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: kind.icon)
                .font(.largeTitle)
                .foregroundStyle(Color.appTextTertiary(scheme))
            Text(emptyText)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary(scheme))
            Text("这个列表由论坛的「我的中心」提供，客户端不显示任何示例数据。")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.appTextTertiary(scheme))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("my-space-empty")
    }

    private var emptyText: String {
        switch kind {
        case .threads: return "你在本站还没有发表过主题"
        case .replies: return "你在本站还没有回复过"
        case .friends: return "你还没有添加好友"
        case .follows: return "你还没有关注的人"
        }
    }

    private var loginView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(Color.appTextTertiary(scheme))
            Text("需要登录")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary(scheme))
            Text("「\(kind.listTitle)」来自论坛的我的中心，必须登录后才能读取。登录后回来即可看到真实内容。")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.appTextSecondary(scheme))
            Button {
                showLogin = true
            } label: {
                Text("登录 4D4Y 账号")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appPrimary(scheme))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            .padding(.top, 4)
            .accessibilityIdentifier("my-space-login")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.appTextTertiary(scheme))
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.appTextSecondary(scheme))
            Button("重试") {
                Task { await load() }
            }
            .font(.subheadline)
            .foregroundStyle(Color.appPrimary(scheme))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageForMissingSection(_ name: String) -> String {
        "本站论坛用的是 Discuz! 7.2，它的「我的中心」里没有「\(name)」这个栏目，"
        + "所以客户端不会给你一个空列表——那是假的。需要看的话，可以到论坛网页版里操作。"
    }
}
