import SwiftUI

/// 顶部板块切换条：横向胶囊，选中高亮紫色，可左右滑动。
/// 点选即触发 `onSelect`（通常同时刷新该板块内容）。
struct BoardChips: View {
    let boards: [String]
    @Binding var selected: String
    var onSelect: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(boards, id: \.self) { board in
                    Button {
                        selected = board
                        onSelect(board)
                    } label: {
                        Text(board)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(selected == board ? Color.appPrimary(scheme) : Color.appSurfaceSecondary(scheme))
                            .foregroundStyle(selected == board ? Color.white : Color.appTextPrimary(scheme))
                            .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
