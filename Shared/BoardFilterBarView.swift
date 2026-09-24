import SwiftUI

/// 板块页排序条：热门 / 一天 / 两天 / 周 / 月 / 季。
///
/// 内容全部来自板块页自身的链接（见 `BoardFilterParser`），客户端不拼参数。
/// 选中态同样以页面为准（`option.isSelected`），不在客户端记账：
/// 点一下就是请求那个链接，然后由**返回的页面**告诉我们当前选中的是谁。
///
/// ⚠️ 2026-09-24 修订：**主题分类不在这条上**。用户明确「标签不用在首页显示，
/// 是在发帖的时候选」—— 分类已挪到发帖页的下拉（`NewPostView`）。
struct BoardFilterBarView: View {
    let bar: BoardFilterBar
    /// 点击某一项（调用方据此请求 `option.path`）。
    var onSelect: (BoardFilterOption) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(bar.sorts) { chip($0) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            // 板块切换或排序变化后，把当前选中项滚到视野中间。
            .onChange(of: bar) { _, newValue in
                guard let selected = newValue.sorts.first(where: { $0.isSelected }) else { return }
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
