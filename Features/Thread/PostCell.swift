import SwiftUI
import SwiftData

/// 单个楼层的阅读单元。
///
/// 组合：`PostHeader`（头像/用户名/时间/楼层）+ `Divider` + `PostContent`（正文/图片）。
/// 论坛阅读风格：无 Card 背景，仅以 `Divider` 分隔头部与正文；整体靠 `List` 行间距形成楼层节奏。
/// 长按弹出菜单可屏蔽 / 取消屏蔽该楼层作者（仅本地 `BlockedUser`，不影响服务器数据）。
struct PostCell: View {
    let post: Post
    /// 是否已被本地 `BlockedUser` 屏蔽（父视图基于 `post.authorID` 计算后传入）。
    let isBlocked: Bool
    /// 点击图片缩略图时的回调。
    let onImageTap: (URL) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query private var settings: [LocalSettings]

    /// 楼层纵向间距随「列表密度」联动：紧凑 6 / 标准 10 / 宽松 14。
    private var floorPadding: CGFloat {
        switch settings.first?.listDensity ?? "normal" {
        case "compact": return 6
        case "comfortable": return 14
        default: return 10
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PostHeader(post: post)
            Divider()
                .background(Color.appDivider(scheme))
            PostContent(post: post, isBlocked: isBlocked, onImageTap: onImageTap)
        }
        .padding(.vertical, floorPadding)
        .contextMenu { contextMenuContent }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if let uid = post.authorID {
            if isBlocked {
                Button {
                    BlockedUser.unblock(uid: uid, context: modelContext)
                } label: {
                    Label("取消屏蔽", systemImage: "eye")
                }
            } else {
                Button {
                    BlockedUser.block(uid: uid, username: post.authorName, context: modelContext)
                } label: {
                    Label("屏蔽作者", systemImage: "eye.slash")
                }
            }
        }
    }
}
