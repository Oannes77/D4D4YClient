import SwiftUI

/// 可折叠的「搜索 + 发帖」一行。
///
/// 布局（下拉展开时）：
/// ```
/// [🔍 搜索 Discovery            ]  [发帖]
/// ```
/// 搜索框占满左侧、发帖按钮固定在右端 —— 这一行**默认完全收起**（`collapsed == true`），
/// 只有首页顶部**下拉回弹**才出现。收起时既看不到搜索、也看不到发帖按钮，
/// 首屏所有纵向空间都留给帖子内容（这是用户明确要的形态）。
///
/// ⚠️ 因此发帖入口与搜索是同一个可见性：想发帖要先下拉。2026-09-24 用户确认如此。
struct CollapsibleSearch: View {
    @Binding var text: String
    let collapsed: Bool
    /// 占位提示（默认按当前板块提示）。
    var placeholder: String = "搜索 4D4Y"
    /// 回车提交（进入搜索结果页）。
    var onSubmit: () -> Void = {}
    /// 发帖按钮的动作。为 nil 时不显示发帖按钮（例如详情页复用本组件时）。
    var onCompose: (() -> Void)?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            if !collapsed {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.appTextTertiary(scheme))
                        TextField(placeholder, text: $text)
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextPrimary(scheme))
                            .textInputAutocapitalization(.never)
                            .submitLabel(.search)
                            .onSubmit { onSubmit() }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Color.appSurfaceSecondary(scheme))
                    .cornerRadius(10)

                    if let onCompose {
                        Button(action: onCompose) {
                            Text("发帖")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.appPrimary(scheme))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home-compose-entry")
                    }
                }
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
