import SwiftUI

/// 首页发帖入口（Threads 风格）：左侧当前用户头像 + 右侧「发新帖…」胶囊。
///
/// 取代原先右下角的紫色悬浮按钮（`ComposeFAB`）：
/// FAB 固定在右下角，**必然压住列表正文**（验收截图里盖住了第 2 条的标题与摘要），
/// 这是悬浮按钮的固有代价；而这一条随列表一起铺满整行、不吃内容位，
/// 点一下同样进发帖页 —— 功能不减，遮挡消失。
///
/// 未登录 / 拿不到 uid 时头像走 `AvatarView` 的中性默认头像，不伪造真人头像。
struct ComposeEntryBar: View {
    /// 当前用户 UID（未登录传 nil）。
    let authorID: Int?
    /// 当前用户名（仅头像回退时展示用）。
    let authorName: String
    /// 占位文案。
    var placeholder: String = "发新帖…"
    /// 点击入口的动作（打开发帖页）。
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AvatarView(authorID: authorID, authorName: authorName, size: 34)

                Text(placeholder)
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextTertiary(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 14)
                    .background(Color.appSurfaceSecondary(scheme))
                    .clipShape(Capsule())
            }
            // 整行可点（不只胶囊文字），符合「一条入口」的预期热区。
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .accessibilityIdentifier("home-compose-entry")
        .accessibilityLabel("发新帖")
    }
}
