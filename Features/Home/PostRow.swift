import SwiftUI
import SwiftData

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
    /// 是否已在本机收藏（决定星标空心 / 实心）。
    var isSaved: Bool = false
    /// 帖子网页地址（系统分享用）；拿不到时隐藏分享按钮，不摆设空按钮。
    var threadURL: URL? = nil
    /// 点星标：切换本地收藏（与详情页同一份数据）。
    var onToggleSave: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    /// 本地偏好：列表是否显示帖子正文预览（我的 → 显示帖子正文）。
    @ObservedObject private var prefs = PreferenceStore.shared
    /// 阅读设置：列表密度（我的 → 主题外观 → 列表密度）。
    @Query private var settings: [LocalSettings]

    /// 行内纵向留白随「列表密度」联动：紧凑 8 / 标准 12 / 宽松 18。
    /// 与 `PostCell` / `ThreadListView` 同一口径，避免同一设置在各个列表表现不一致。
    private var densityPadding: CGFloat {
        switch settings.first?.listDensity ?? "normal" {
        case "compact": return 8
        case "comfortable": return 18
        default: return 12
        }
    }

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

            // 预览正文（3 行截断 + …）；真实列表页无正文时（尚未检测）不占空行；
            // 「我的 → 显示帖子正文」关闭后只显示标题，省屏幕。
            if prefs.showPostContent, !item.previewBody.isEmpty {
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

            // 操作栏（全图标 + 必要数字）。
            // 分享 / 收藏 都是真做的事：分享走系统分享面板，收藏写本地书签（与详情页同源）。
            HStack(spacing: 22) {
                Button { onReply() } label: {
                    Image(systemName: "bubble.right")
                    Text("\(item.replies)").font(.caption)
                }
                .foregroundStyle(Color.appTextSecondary(scheme))

                if let threadURL {
                    ShareLink(item: threadURL) {
                        Image(systemName: "arrowshape.turn.up.right")
                    }
                    .foregroundStyle(Color.appTextSecondary(scheme))
                }

                Button { onToggleSave() } label: {
                    Image(systemName: isSaved ? "star.fill" : "star")
                }
                .foregroundStyle(isSaved ? Color.appGold(scheme) : Color.appTextSecondary(scheme))

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
        .padding(.vertical, densityPadding)
        .padding(.horizontal, 16)
    }
}
