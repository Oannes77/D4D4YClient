import SwiftUI

/// 首页信息流单帖（Threads 风格卡片行）。
///
/// 点击区域（遵循 2026-09-18 锁定交互）：
/// - 标题 / 正文 / 图片 / 附件 → 进详情（`onOpen`）
/// - 回复数图标 → 进详情并跳最后回复（`onReply`）
/// - 作者头像 / 作者名 → 弹用户卡（`onUser`）
struct PostRow: View {
    let item: HomeThreadItem
    var onOpen: () -> Void
    var onReply: () -> Void
    var onUser: (Int, String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 头部：头像 + 名 + 分组 + 时间 + 板块
            HStack(alignment: .top, spacing: 10) {
                AvatarView(authorID: item.authorID, authorName: item.authorName, size: 42)
                    .onTapGesture { if let uid = item.authorID { onUser(uid, item.authorName) } }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(item.authorName)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(Color.appTextPrimary(scheme))
                            .onTapGesture { if let uid = item.authorID { onUser(uid, item.authorName) } }
                        if let group = item.authorGroup {
                            Text("· \(group)")
                                .font(.caption)
                                .foregroundStyle(Color.appTextSecondary(scheme))
                        }
                        Spacer()
                        if !item.createdAtRaw.isEmpty {
                            Text(item.createdAtRaw)
                                .font(.caption2)
                                .foregroundStyle(Color.appTextTertiary(scheme))
                        }
                    }
                    if !item.boardName.isEmpty {
                        Text(item.boardName)
                            .font(.caption2)
                            .foregroundStyle(Color.appTextTertiary(scheme))
                    }
                }
            }

            // 标题（加粗首行）
            Button { onOpen() } label: {
                Text(item.title)
                    .font(.headline).fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary(scheme))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("home-post-open")

            // 预览正文（3 行截断 + …）；真实列表页无正文时（尚未检测）不占空行
            if !item.previewBody.isEmpty {
                Button { onOpen() } label: {
                    Text(item.previewBody)
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextPrimary(scheme))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // 单图（点击进详情）
            if item.hasImage, let url = item.imageURL {
                Button { onOpen() } label: {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Color.appSurfaceSecondary(scheme))
                    }
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(12)
                }
            }

            // 附件：仅回形针图标（不显示文字 / 数量）
            if item.hasAttachment {
                Button { onOpen() } label: {
                    Image(systemName: "paperclip")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary(scheme))
                }
            }

            // 操作栏（全图标 + 必要数字）
            HStack(spacing: 22) {
                Button { onReply() } label: {
                    Image(systemName: "bubble.right")
                    Text("\(item.replies)").font(.caption)
                }
                .foregroundStyle(Color.appTextSecondary(scheme))

                Button { } label: {
                    Image(systemName: "arrowshape.turn.up.right")
                }
                .foregroundStyle(Color.appTextSecondary(scheme))

                Button { } label: {
                    Image(systemName: "star")
                }
                .foregroundStyle(Color.appTextSecondary(scheme))

                HStack(spacing: 3) {
                    Image(systemName: "diamond")
                    if let points = item.points {
                        Text("\(points)").font(.caption)
                    }
                }
                .foregroundStyle(Color.appGold(scheme))

                if let views = item.views {
                    HStack(spacing: 3) {
                        Image(systemName: "eye")
                        Text("\(views)").font(.caption)
                    }
                    .foregroundStyle(Color.appTextSecondary(scheme))
                }

                Spacer()
            }
            .font(.subheadline)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}
