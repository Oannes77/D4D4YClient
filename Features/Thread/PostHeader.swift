import SwiftUI

/// 楼层头部：作者头像 + 用户名 + 时间 + 楼层编号。
///
/// 论坛阅读风格：纯横向信息条，无 Card 背景；
/// 楼层编号以品牌主色呈现（非胶囊/色块），与正文之间由 `PostCell` 的 `Divider` 分隔。
struct PostHeader: View {
    let post: Post
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AvatarView(authorID: post.authorID, authorName: post.authorName, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(post.authorName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appTextPrimary(scheme))
                    .lineLimit(1)
                if !post.createdAtRaw.isEmpty {
                    Text(post.createdAtRaw)
                        .font(.caption2)
                        .foregroundStyle(Color.appTextSecondary(scheme))
                }
            }

            Spacer()

            Text(post.floor.map { "#\($0)" } ?? "--")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.appPrimary(scheme))
        }
    }
}
