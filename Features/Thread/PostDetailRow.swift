import SwiftUI

/// 帖子详情楼层行（Threads 会话视图）。
///
/// 头部：头像 + 作者名 + 「眼睛」(只看该作者) + 时间 + 楼层。
/// 正文：复用 `PostContent`（正文 + 本楼层图片缩略图，点击进全屏画廊）。
/// 操作栏：回复 / 分享 / 收藏 / 关注 / 举报 —— 每一个都做**真实的事**，没有假按钮：
/// - 回复：弹回复 Sheet；
/// - 分享：菜单二选一 —— 系统分享，或**站内分享给好友**（读好友列表 → 发私信配链接）；
/// - 收藏：论坛服务器收藏（`my.php?item=favorites&type=thread`），需要登录，结果以回读确认为准；
/// - 关注：**关注该主题的新回复**（站点原文 `my.php?item=attention&action=add&tid=<tid>`），
///   同样需要登录、同样以回读关注列表为准。⚠️「关注」关注的是**主题**（参数 tid），不是人；
/// - 举报：论坛没有举报接口 → 复制该帖链接 + 私信管理员（未配置收件人时只复制并提示）。
///
/// ⚠️ 2026-09-24 起**取消第六项「网页版」**（`safari` 图标）：它当初存在的理由是
/// 「站内评分等只在论坛网页端提供」，但复核后确认**该站点两套模板都没有评分功能**
/// （见 `FeatureStatus.md` 模块 17），即它指向的能力并不存在 ⇒ 按「不留没用的入口」删掉。
/// `threadURL` 仍保留 —— 系统分享与举报都要用它。
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
    /// 是否已收藏（论坛服务器 `my.php?item=favorites&type=thread`）。
    let isSaved: Bool
    /// 是否已关注该主题的新回复（论坛服务器 `my.php?item=attention`）。
    let isAttended: Bool
    @Binding var onlyAuthorUID: Int?
    var onUser: (Int, String) -> Void
    var onReply: () -> Void
    var onQuote: (Post) -> Void
    var onImagesTap: ([URL], Int) -> Void
    var onToggleSave: () -> Void
    /// 关注 / 取消关注该主题的新回复（服务器 `my.php?item=attention`）。
    var onToggleAttention: () -> Void
    /// 取消本地拉黑（由父视图写入 `BlockedUser`，仅本地拉黑时会出现）。
    var onUnblock: () -> Void
    /// 站内分享给好友（读好友列表 → 发私信）。
    var onShareToBuddy: () -> Void
    /// 举报该帖（复制链接 + 私信管理员）。
    var onReport: () -> Void

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
            PostContent(post: post, isBlocked: isBlocked, onUnblock: onUnblock,
                        onImagesTap: onImagesTap, syncWhenDemo: isOP)

            actionBar
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .onLongPressGesture { onQuote(post) }
    }

    // MARK: - 操作栏（全图标）

    private var actionBar: some View {
        // 五个图标（回复 / 分享 / 收藏 / 关注 / 举报），间距 18 才不会在窄屏上挤到换行。
        HStack(spacing: 18) {
            Button { onReply() } label: {
                Image(systemName: "bubble.right")
            }
            .foregroundStyle(Color.appTextSecondary(scheme))
            .accessibilityIdentifier("post-reply")

            // 分享：菜单二选一 —— 系统分享 / 站内分享给好友（论坛的站内分享只能发给好友）
            Menu {
                if let threadURL {
                    ShareLink(item: threadURL) {
                        Label("系统分享", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    onShareToBuddy()
                } label: {
                    Label("分享给好友", systemImage: "person.2")
                }
            } label: {
                Image(systemName: "arrowshape.turn.up.right")
            }
            .foregroundStyle(Color.appTextSecondary(scheme))
            .accessibilityIdentifier("post-share")

            // 收藏：论坛**服务器**收藏（回读列表确认，本地的 SavedThread 已弃用）
            Button {
                onToggleSave()
            } label: {
                Image(systemName: isSaved ? "star.fill" : "star")
            }
            .foregroundStyle(isSaved ? Color.appGold(scheme) : Color.appTextSecondary(scheme))
            .accessibilityIdentifier("post-save")

            // 关注该主题的新回复（站点原文 my.php?item=attention&action=add&tid=）
            // 与收藏同为服务器数据，需登录；结果同样以回读关注列表为准。
            Button {
                onToggleAttention()
            } label: {
                Image(systemName: isAttended ? "bell.fill" : "bell")
            }
            .foregroundStyle(isAttended ? Color.appPrimary(scheme) : Color.appTextSecondary(scheme))
            .accessibilityIdentifier("post-attention")

            // 举报：论坛没有举报接口 → 复制帖子链接 + 私信管理员
            Button {
                onReport()
            } label: {
                Image(systemName: "exclamationmark.bubble")
            }
            .foregroundStyle(Color.appTextSecondary(scheme))
            .accessibilityIdentifier("post-report")

            Spacer()
        }
        .font(.subheadline)
    }
}
