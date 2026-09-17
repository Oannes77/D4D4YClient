import SwiftUI

/// 作者头像组件。
///
/// 4D4Y 真实头像接口（Sprint 8 经真实页面抓取确认）：
/// Discuz! UCenter 把头像以静态文件形式存放在 CDN 上，路径规则为：
///   https://img02.4d4y.com/forum/uc_server/data/avatar/{9位零填充UID，每3位加斜杠}/{uid}_avatar_{size}.jpg
/// 例如 uid=3 → 000/00/00/03_avatar_middle.jpg；size ∈ {small, middle, big}。
/// 这与本仓库早期假设的 `uc_server/avatar.php?uid=xxx` 动态脚本不同 —— 已废弃。
///
/// 设计约束：
/// - 优先加载真实头像；无 uid、加载失败或用户无头像时回退到中性默认头像（系统图标），不生成真人头像。
/// - 统一圆形裁切。
struct AvatarView: View {
    let authorID: Int?
    let authorName: String
    var size: CGFloat = 40

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let uid = authorID, let url = Self.avatarURL(uid: uid) {
            AsyncImage(url: url) { phase in
                avatarImage(for: phase)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .background(Color.appSurface(scheme))
        } else {
            defaultNeutralAvatar
        }
    }

    /// 真实头像尺寸（Discuz UCenter 三档）。
    enum AvatarSize: String {
        case small  = "small"   // 48px，列表可用
        case middle = "middle"  // 120px，详情/40pt 显示下更清晰
        case big    = "big"     // 200px
    }

    /// 按 4D4Y 真实静态路径构造头像 URL。
    /// - 规则：9 位零填充 UID，每 3 位插入斜杠，后缀 `_avatar_{size}.jpg`。
    private static func avatarURL(uid: Int, size: AvatarSize = .middle) -> URL? {
        let padded = String(format: "%09d", max(uid, 0))
        let p1 = String(padded.prefix(3))
        let p2 = String(padded.dropFirst(3).prefix(3))
        let p3 = String(padded.suffix(3))
        let host = "https://img02.4d4y.com/forum/uc_server/data/avatar/\(p1)/\(p2)/\(p3)_avatar_\(size.rawValue).jpg"
        return URL(string: host)
    }

    @ViewBuilder
    private func avatarImage(for phase: AsyncImagePhase) -> some View {
        switch phase {
        case .success(let image):
            image
                .resizable()
                .scaledToFill()
        case .failure, .empty:
            defaultNeutralAvatar
        @unknown default:
            defaultNeutralAvatar
        }
    }

    /// 中性默认头像：系统人形图标 + 圆形裁切。不生成任何真人/随机头像。
    private var defaultNeutralAvatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Color.appTextTertiary(scheme))
            .background(Color.appSurfaceSecondary(scheme))
            .clipShape(Circle())
    }
}
