import SwiftUI

/// 帖子详情楼层行（Threads 会话视图）。
///
/// 头部：头像 + 作者名 + 「眼睛」(只看该作者) + 时间 + 楼层。
/// 正文：复用 `PostContent`（正文 + 本楼层图片缩略图，点击进全屏画廊）。
/// 操作栏：回复 / 分享 / 收藏 / 网页版 —— 四个都做**真实的事**，没有假按钮：
/// - 回复：弹回复 Sheet；
/// - 分享：系统分享面板，分享该帖网页链接（论坛模板已整块注释掉原生「站内转发 / 分享」，
///   故不做「假装转发成功」，改用系统分享，功能等价且真实可用）；
/// - 收藏：本地书签（`SavedThread`），写本地 SwiftData，不伪造服务器收藏成功；
/// - 网页版：在浏览器打开该帖，论坛原生功能（评分 / 举报 / 收藏）在网页端完成。
///
/// - 长按整行 → 引用该楼（弹回复 Sheet，预填引用文本）。
/// - 点作者头像 / 名 → 用户卡。
/// - 点头部「眼睛」→ 只看该作者（互斥，再点取消）。
struct PostDetailRow: View {
    let post: Post
    let isOP: Bool
    /// 该楼作者是否已被本地 `BlockedUser` 屏蔽（由父视图算好后传入）。
    let isBlocked: Bool
    /// 帖子网页地址（分享 / 浏览器打开都指向它）；为 nil（拿不到 tid）时隐藏这两个按钮。
    let threadURL: URL?
    /// 是否已本地收藏。
    let isSaved: Bool
    @Binding var onlyAuthorUID: Int?
    var onUser: (Int, String) -> Void
    var onReply: () -> Void
    var onQuote: (Post) -> Void
    var onImagesTap: ([URL], Int) -> Void
    var onToggleSave: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var isOnly: Bool { onlyAuthorUID == post.authorID && onlyAuthorUID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 头部
            HStack(alignment: .center, spacing: 10) {
                AvatarView(authorID: post.authorID, authorName: post.authorName, size: 40)
                    .onTapGesture { if let uid = post.authorID { onUser(uid, post.authorName) } }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(post.authorName)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(Color.appTextPrimary(scheme))
                            .onTapGesture { if let uid = post.authorID { onUser(uid, post.authorName) } }

                        Button {
                            onlyAuthorUID = (onlyAuthorUID == post.authorID ? nil : post.authorID)
                        } label: {
                            Image(systemName: "eye")
                                .font(.footnote)
                                .foregroundStyle(isOnly ? Color.appPrimary(scheme) : Color.appTextTertiary(scheme))
                                .padding(4)
                                .background(isOnly ? Color.appPrimary(scheme).opacity(0.12) : Color.clear)
                                .cornerRadius(6)
                        }

                        Spacer()

                        Text(post.floor.map { "#\($0)" } ?? (isOP ? "楼主" : "--"))
                            .font(.caption).fontWeight(.bold)
                            .foregroundStyle(Color.appPrimary(scheme))
                    }

                    if !post.createdAtRaw.isEmpty {
                        Text(post.createdAtRaw)
                            .font(.caption2)
                            .foregroundStyle(Color.appTextSecondary(scheme))
                    }
                }
            }

            // 正文（含本楼层图片，点图进全屏画廊）
            PostContent(post: post, isBlocked: isBlocked,
                        onImagesTap: onImagesTap, syncWhenDemo: isOP)

            actionBar
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .onLongPressGesture { onQuote(post) }
    }

    // MARK: - 操作栏（全图标）

    private var actionBar: some View {
        HStack(spacing: 28) {
            Button { onReply() } label: {
                Image(systemName: "bubble.right")
            }
            .foregroundStyle(Color.appTextSecondary(scheme))
            .accessibilityIdentifier("post-reply")

            // 分享：系统分享面板（分享该帖网页链接）
            if let threadURL {
                ShareLink(item: threadURL) {
                    Image(systemName: "arrowshape.turn.up.right")
                }
                .foregroundStyle(Color.appTextSecondary(scheme))
                .accessibilityIdentifier("post-share")
            }

            // 收藏：本地书签（写本地 SwiftData，不假装服务器已收藏）
            Button {
                onToggleSave()
            } label: {
                Image(systemName: isSaved ? "star.fill" : "star")
            }
            .foregroundStyle(isSaved ? Color.appGold(scheme) : Color.appTextSecondary(scheme))
            .accessibilityIdentifier("post-save")

            // 网页版：站内评分 / 举报等只在论坛网页端提供，直接打开该帖
            if let threadURL {
                Link(destination: threadURL) {
                    Image(systemName: "safari")
                }
                .foregroundStyle(Color.appTextSecondary(scheme))
                .accessibilityIdentifier("post-web")
            }

            Spacer()
        }
        .font(.subheadline)
    }
}
