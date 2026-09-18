import SwiftUI

/// 首页右下角紫色发帖悬浮按钮（FAB）。
/// 仅出现在首页帖子列表，帖子详情等页面不显示，避免遮挡看帖。
struct ComposeFAB: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Color.appPrimary(scheme))
                .clipShape(Circle())
        }
    }
}
