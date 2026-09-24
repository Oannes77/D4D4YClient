import SwiftUI

/// 顶部板块切换条：横向胶囊，选中高亮紫色。
///
/// 交互（2026-09-20 用户确认口径）：
/// - **点击**某个胶囊 → 进入该板块（上层刷新该板块最近动态）；
/// - **在胶囊条上左右滑** → 切换到上一个 / 下一个板块，滑块自动居中到当前选中的胶囊。
struct BoardChips: View {
    let boards: [BoardChipItem]
    @Binding var selectedID: Int
    var onSelect: (BoardChipItem) -> Void
    /// 在胶囊条上左右滑：+1 = 下一个板块，-1 = 上一个板块。
    var onSwipe: (Int) -> Void = { _ in }
    /// 需要登录才能访问的版块（游客身份下显示一把小锁）。
    /// 只是**提示**，不阻止点击 —— 点进去由服务器返回提示页，界面照原文显示 + 给登录入口。
    var lockedIDs: Set<Int> = []

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(boards) { board in
                        Button {
                            selectedID = board.id
                            onSelect(board)
                        } label: {
                            HStack(spacing: 5) {
                                if lockedIDs.contains(board.id) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                Text(board.name)
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(selectedID == board.id ? Color.appPrimary(scheme) : Color.appSurfaceSecondary(scheme))
                            .foregroundStyle(selectedID == board.id ? Color.white : Color.appTextPrimary(scheme))
                            .cornerRadius(20)
                        }
                        .id(board.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            // 在胶囊条上横向滑动即切换板块。
            // 阈值取 60pt：小幅拖动仍可正常滚动胶囊条去够远处的板块，不会误触发切换。
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                        onSwipe(dx < 0 ? 1 : -1)
                    }
            )
            // 选中项变化（点击或滑动）后，滑块居中到当前胶囊，保证它总在视野内。
            .onChange(of: selectedID) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}
