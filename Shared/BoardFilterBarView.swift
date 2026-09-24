import SwiftUI

/// 板块页筛选条：**主题分类在前**，排序与时间在后。
///
/// 内容全部来自板块页自身的链接（见 `BoardFilterParser`），客户端不拼参数、不硬编码分类表
/// —— 每个板块的分类都不一样，硬编码必然错。
///
/// 选中态同样以页面为准（`option.isSelected`），不在客户端记账：
/// 点一下就是请求那个链接，然后由**返回的页面**告诉我们当前选中的是谁。
struct BoardFilterBarView: View {
    let bar: BoardFilterBar
    /// 点击某一项（调用方据此请求 `option.path`）。
    var onSelect: (BoardFilterOption) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(bar.categories) { chip($0) }
                    if !bar.categories.isEmpty, !bar.sorts.isEmpty {
                        Rectangle()
                            .fill(Color.appDivider(scheme))
                            .frame(width: 1, height: 16)
                            .padding(.horizontal, 2)
                    }
                    ForEach(bar.sorts) { chip($0) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            // 板块切换或筛选变化后，把当前选中项滚到视野中间（分类可能十几个，不滚就看不见选中谁）。
            .onChange(of: bar) { _, newValue in
                let all = newValue.categories + newValue.sorts
                guard let selected = all.first(where: { $0.isSelected }) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(selected.id, anchor: .center)
                }
            }
        }
        .accessibilityIdentifier("board-filter")
    }

    private func chip(_ option: BoardFilterOption) -> some View {
        Button {
            onSelect(option)
        } label: {
            Text(option.title)
                .font(.footnote)
                .fontWeight(option.isSelected ? .semibold : .regular)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(option.isSelected ? Color.appPrimary(scheme)
                                              : Color.appSurfaceSecondary(scheme))
                .foregroundStyle(option.isSelected ? Color.white
                                                   : Color.appTextPrimary(scheme))
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}
