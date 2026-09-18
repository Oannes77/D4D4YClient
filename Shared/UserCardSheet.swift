import SwiftUI

/// 点击作者头像 / 名弹出的紧凑用户卡。
/// 布局：头像 + 名 + 签名(单行…) / 信息框(UID·分组·帖数·积分) / 功能键(加好友·私信·搜贴·拉黑)。
/// 论坛无 @username 体系，不显示 @handle。
struct UserCardSheet: View {
    let userID: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var user: DemoUser { DemoUsers.dict[userID] ?? DemoUsers.fallback }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    AvatarView(authorID: user.uid, authorName: user.name, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.name)
                            .font(.title3).fontWeight(.bold)
                            .foregroundStyle(Color.appTextPrimary(scheme))
                        Text(user.signature)
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary(scheme))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                }

                // 信息框（UID / 分组 / 帖数 / 积分）
                HStack(spacing: 0) {
                    infoCell("UID", user.uidString)
                    Divider().frame(height: 28)
                    infoCell("分组", user.group)
                    Divider().frame(height: 28)
                    infoCell("帖数", "\(user.posts)")
                    Divider().frame(height: 28)
                    infoCell("积分", "\(user.points)")
                }
                .padding(.vertical, 10)
                .background(Color.appSurfaceSecondary(scheme))
                .cornerRadius(12)

                // 功能键（独立一行）
                HStack(spacing: 10) {
                    funcBtn("加好友", "person.badge.plus")
                    funcBtn("私信", "envelope")
                    funcBtn("搜贴", "magnifyingglass")
                    funcBtn("拉黑", "nosign")
                }

                Spacer()
            }
            .padding(16)
        }
    }

    private func infoCell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(Color.appTextTertiary(scheme))
            Text(value).font(.subheadline).fontWeight(.medium)
                .foregroundStyle(Color.appTextPrimary(scheme))
        }
        .frame(maxWidth: .infinity)
    }

    private func funcBtn(_ title: String, _ icon: String) -> some View {
        Button { } label: {
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
    }
}

// MARK: - Demo 用户数据（离线样例，接真实会员信息后替换）
private struct DemoUser {
    let uid: Int
    let name: String
    let group: String
    let posts: Int
    let points: Int
    let signature: String
    var uidString: String { "\(uid)" }
}

private enum DemoUsers {
    static let dict: [Int: DemoUser] = [
        1024: DemoUser(uid: 1024, name: "老橡树", group: "论坛元老", posts: 328, points: 9520, signature: "键盘会老，手感永存。"),
        2077: DemoUser(uid: 2077, name: "Kepler", group: "高级会员", posts: 156, points: 4310, signature: "iPod 收藏爱好者，求电池教程。"),
        888:  DemoUser(uid: 888, name: "Discovery控", group: "论坛元老", posts: 540, points: 12030, signature: "Discovery 版块的灵魂守护者。"),
        522:  DemoUser(uid: 522, name: "麦客爱苹果", group: "中级会员", posts: 92, points: 1880, signature: "麦客一枚，折腾不止。"),
        6666: DemoUser(uid: 6666, name: "我的账号", group: "新手上路", posts: 12, points: 120, signature: "这是我的个性签名。")
    ]
    static let fallback = DemoUser(uid: 0, name: "匿名", group: "游客", posts: 0, points: 0, signature: "")
}
