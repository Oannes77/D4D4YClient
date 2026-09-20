import SwiftUI
import Combine

/// 用户卡视图模型：真实 `space.php?uid=NNN`（需登录）。
@MainActor
final class UserCardViewModel: ObservableObject {

    enum CardState: Equatable {
        case idle
        case loading
        case loaded(UserProfile)
        case requiresLogin
        case failed(String)
    }

    @Published private(set) var state: CardState = .idle

    private let repository: ProfileRepositoryProtocol

    init(repository: ProfileRepositoryProtocol = ProfileRepository()) {
        self.repository = repository
    }

    func load(uid: Int, fallbackName: String) async {
        if DemoMode.isOn {
            state = .loaded(DemoData.userProfileDemo(uid: uid, name: fallbackName))
            return
        }
        guard uid > 0 else {
            state = .failed("这个作者没有公开的 UID，无法查看资料。")
            return
        }
        state = .loading
        switch await repository.profile(uid: uid, fallbackName: fallbackName) {
        case .success(let profile):
            state = .loaded(profile)
        case .failure(let error):
            Log.network.error("用户卡资料加载失败: \(String(describing: error), privacy: .public)")
            state = (error == .requiresLogin) ? .requiresLogin : .failed(error.localizedDescription)
        }
    }
}

/// 点击作者头像 / 名弹出的紧凑用户卡。
///
/// 布局：头像 + 名 + 签名(单行…) / 信息框(UID·分组·帖数·积分) / 功能键(加好友·私信·搜贴·拉黑)。
/// 论坛无 @username 体系，不显示 @handle。
///
/// **不再使用内置示例资料**：真实模式下资料来自 `space.php`；
/// 未登录或解析不到时只显示已经确定的信息（用户名 + UID）并给出登录入口，
/// 不拿「328 帖 / 9520 积分」这类编造数字冒充。
struct UserCardSheet: View {
    let userID: Int
    let fallbackName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @StateObject private var viewModel = UserCardViewModel()
    @State private var showLogin = false
    @State private var showChat = false

    init(userID: Int, fallbackName: String = "该用户") {
        self.userID = userID
        self.fallbackName = fallbackName
    }

    private var profile: UserProfile? {
        if case .loaded(let profile) = viewModel.state { return profile }
        return nil
    }

    private var displayName: String {
        let name = profile?.name ?? fallbackName
        return name.isEmpty ? "该用户" : name
    }

    var body: some View {
        // 底部小弹窗：固定 detent 高度，只弹出能浏览完资料的高度，不占整屏。
        VStack(spacing: 14) {
            header
            infoBox
            actionRow
        }
        .padding(16)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .task { await viewModel.load(uid: userID, fallbackName: fallbackName) }
        .sheet(isPresented: $showLogin) { LoginView() }
        .sheet(isPresented: $showChat) {
            NavigationStack {
                MessageChatView(userID: userID, userName: displayName)
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 12) {
            AvatarView(authorID: userID, authorName: displayName, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.title3).fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary(scheme))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(viewModel.state == .requiresLogin
                                     ? Color.appPrimary(scheme)
                                     : Color.appTextSecondary(scheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()
        }
    }

    private var subtitle: String {
        switch viewModel.state {
        case .idle, .loading:
            return "正在读取资料…"
        case .requiresLogin:
            return "登录后可查看完整资料"
        case .failed:
            return "资料暂时读不出来"
        case .loaded(let profile):
            if let signature = profile.signature, !signature.isEmpty { return signature }
            if let group = profile.group, !group.isEmpty { return group }
            return "UID \(profile.uid)"
        }
    }

    // MARK: - 信息框

    /// 只列**确实取到**的字段；取不到的整格不显示（不填示例数字）。
    private var infoCells: [(String, String)] {
        guard let profile else { return [] }
        var cells: [(String, String)] = [("UID", "\(profile.uid)")]
        if let group = profile.group, !group.isEmpty { cells.append(("分组", group)) }
        if let posts = profile.posts { cells.append(("帖数", "\(posts)")) }
        if let points = profile.points { cells.append(("积分", "\(points)")) }
        return cells
    }

    @ViewBuilder
    private var infoBox: some View {
        if infoCells.isEmpty {
            Button {
                if viewModel.state == .requiresLogin { showLogin = true }
            } label: {
                Text(infoPlaceholder)
                    .font(.caption)
                    .foregroundStyle(viewModel.state == .requiresLogin
                                     ? Color.appPrimary(scheme)
                                     : Color.appTextSecondary(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.appSurfaceSecondary(scheme))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.state != .requiresLogin)
            .accessibilityIdentifier("user-card-login")
        } else {
            HStack(spacing: 0) {
                ForEach(Array(infoCells.enumerated()), id: \.offset) { entry in
                    if entry.offset > 0 {
                        Divider().frame(height: 28)
                    }
                    VStack(spacing: 3) {
                        Text(entry.element.0)
                            .font(.caption2)
                            .foregroundStyle(Color.appTextTertiary(scheme))
                        Text(entry.element.1)
                            .font(.subheadline).fontWeight(.medium)
                            .foregroundStyle(Color.appTextPrimary(scheme))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)
            .background(Color.appSurfaceSecondary(scheme))
            .cornerRadius(12)
        }
    }

    private var infoPlaceholder: String {
        switch viewModel.state {
        case .requiresLogin: return "登录后查看 UID / 分组 / 帖数 / 积分"
        case .failed:        return "资料页结构已变化，暂时读不出统计信息"
        default:             return "正在读取资料…"
        }
    }

    // MARK: - 功能键

    private var actionRow: some View {
        HStack(spacing: 10) {
            funcBtn("加好友", "person.badge.plus") { }
            funcBtn("私信", "envelope") { showChat = true }
            funcBtn("搜贴", "magnifyingglass") { }
            funcBtn("拉黑", "nosign") { }
        }
    }

    private func funcBtn(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.subheadline)
                Text(title).font(.caption)
            }
            .foregroundStyle(Color.appPrimary(scheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.appSurfaceSecondary(scheme))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}
