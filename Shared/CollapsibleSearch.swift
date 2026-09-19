import SwiftUI

/// 折叠搜索栏：上推隐藏 / 滚到顶出现，腾出有效信息位。
/// 折叠态由父视图的滚动偏移驱动（`collapsed` 绑定）。
struct CollapsibleSearch: View {
    @Binding var text: String
    let collapsed: Bool
    /// 占位提示（默认按当前板块提示）。
    var placeholder: String = "搜索 4D4Y"
    /// 回车提交（进入搜索结果页）。
    var onSubmit: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            if !collapsed {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.appTextTertiary(scheme))
                    TextField(placeholder, text: $text)
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextPrimary(scheme))
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit { onSubmit() }
                    Spacer()
                }
                .padding(10)
                .background(Color.appSurfaceSecondary(scheme))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .frame(height: collapsed ? 0 : nil, alignment: .top)
        .clipped()
        .background(Color.appBackground(scheme))
        .animation(.easeInOut(duration: 0.2), value: collapsed)
    }
}
