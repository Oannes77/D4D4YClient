import SwiftUI

/// 「-已拉黑-」占位行。
///
/// 用于**用户本地拉黑**（`BlockedUser`）场景：首页 / 板块列表的主题行与帖子详情的楼层，
/// 只要作者在本地黑名单里，就用本视图替换真实内容。
///
/// ⚠️ 与「该帖已被论坛隐藏」严格区分，二者不是一回事：
/// - 本视图 = **用户自己的选择**，随时可以取消（`onUnblock`）；
/// - 「该帖已被论坛隐藏」= **论坛管理员的处罚**（`Post.isBlocked`，作者被禁言 / 帖子被删），
///   客户端只能如实转述，不能也不该提供「取消」出口。
struct BlockedPlaceholderRow: View {

    /// 被拉黑的作者名（可为空，为空时只显示占位文案）。
    let authorName: String
    /// 提供时显示「取消拉黑」按钮；为 nil 时只显示占位文案。
    var onUnblock: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    init(authorName: String = "", onUnblock: (() -> Void)? = nil) {
        self.authorName = authorName
        self.onUnblock = onUnblock
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "nosign")
                .font(.footnote)
                .foregroundStyle(Color.appTextTertiary(scheme))

            Text("-已拉黑-")
                .font(.footnote)
                .foregroundStyle(Color.appTextTertiary(scheme))

            if !authorName.isEmpty {
                Text(authorName)
                    .font(.caption2)
                    .foregroundStyle(Color.appTextTertiary(scheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let onUnblock {
                Button("取消拉黑", action: onUnblock)
                    .font(.caption)
                    .foregroundStyle(Color.appPrimary(scheme))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("unblock-user")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }
}
