import SwiftUI

/// 帖子详情楼层行（Threads 会话视图）。
///
/// 头部：头像 + 作者名 + 「眼睛」(只看该作者) + 时间 + 楼层。
/// 正文：复用 `PostContent`（保留图片/链接/表情等 HTML 渲染）。
/// 操作栏：回复 / 站内转发 / 收藏 / 报告（全图标 + 必要文字）。
/// - 长按整行 → 引用该楼（弹回复 Sheet，预填引用文本）。
/// - 点作者头像 / 名 → 用户卡。
/// - 点头部「眼睛」→ 只看该作者（互斥，再点取消）。
struct PostDetailRow: View {
    let post: Post
    let isOP: Bool
    @Binding var onlyAuthorUID: Int?
    var onUser: (Int, String) -> Void
    var onReply: () -> Void
    var onQuote: (Post) -> Void
    var onImageTap: (URL) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var favorited = false

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

            // 正文
            PostContent(post: post, isBlocked: false, onImageTap: onImageTap, syncWhenDemo: isOP)

            // 操作栏
            HStack(spacing: 28) {
                Button { onReply() } label: {
                    Image(systemName: "bubble.right")
                }
                .foregroundStyle(Color.appTextSecondary(scheme))

                Button { } label: {
                    Image(systemName: "arrowshape.turn.up.right")
                }
                .foregroundStyle(Color.appTextSecondary(scheme))

                Button {
                    favorited.toggle()
                } label: {
                    Image(systemName: favorited ? "star.fill" : "star")
                }
                .foregroundStyle(favorited ? Color.appGold(scheme) : Color.appTextSecondary(scheme))

                Button { } label: {
                    Image(systemName: "exclamationmark.bubble")
                }
                .foregroundStyle(Color.appTextSecondary(scheme))

                Spacer()
            }
            .font(.subheadline)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .onLongPressGesture { onQuote(post) }
    }
}
