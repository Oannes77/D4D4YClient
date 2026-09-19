import SwiftUI

/// 搜索结果页（首页顶部搜索栏 → 结果列表）。
///
/// 复用信息流卡片 `PostRow`，保持与首页一致的 Threads 视觉语言；
/// 顶部显示关键词与结果数。Demo 模式使用 `DemoData.homeFeedDemo()` 离线样例。
struct SearchResultsView: View {
    let keyword: String

    @Environment(\.colorScheme) private var scheme

    init(keyword: String = "X1C") {
        self.keyword = keyword
    }

    private var results: [HomeThreadItem] { DemoData.homeFeedDemo() }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack {
                    Text("“\(keyword)” 的搜索结果")
                        .font(.footnote)
                        .foregroundStyle(Color.appTextSecondary(scheme))
                    Spacer()
                    Text("\(results.count) 条")
                        .font(.footnote)
                        .foregroundStyle(Color.appTextTertiary(scheme))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                ForEach(results) { item in
                    PostRow(item: item, onOpen: {}, onReply: {}, onUser: { _ in })
                    Divider().background(Color.appDivider(scheme))
                }
            }
        }
        .background(Color.appBackground(scheme))
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
    }
}
