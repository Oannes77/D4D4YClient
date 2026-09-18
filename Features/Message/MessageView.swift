import SwiftUI

/// 消息：「站内短信」/「系统消息」分段切换，聚合私信与互动通知。
/// 消息 Tab 红角标显示未读数（由 RootView / ScreenshotGalleryView 的 .badge 呈现）。
struct MessageView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var segment: MessageSeg = .pm

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("消息", selection: $segment) {
                    Text("站内短信").tag(MessageSeg.pm)
                    Text("系统消息").tag(MessageSeg.system)
                }
                .pickerStyle(.segmented)
                .padding(12)
                .background(Color.appBackground(scheme))

                List {
                    switch segment {
                    case .pm:
                        ForEach(MessageData.pm) { MessageRow($0) }
                    case .system:
                        ForEach(MessageData.system) { MessageRow($0) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.appBackground(scheme))
            }
            .navigationTitle("消息")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private enum MessageSeg { case pm, system }

private struct MessageItem: Identifiable {
    let id = UUID()
    let title: String
    let preview: String
    let time: String
    let unread: Bool
}

private enum MessageData {
    static let pm = [
        MessageItem(title: "Discovery控", preview: "你那台 Treo 650 出吗？想要", time: "10:24", unread: true),
        MessageItem(title: "Kepler", preview: "PETG 烘干参数收到了，谢谢！", time: "昨天", unread: false)
    ]
    static let system = [
        MessageItem(title: "回复提醒", preview: "老橡树 回复了你的主题", time: "2 小时前", unread: true),
        MessageItem(title: "收藏提醒", preview: "有人收藏了你的帖子", time: "昨天", unread: false)
    ]
}

private struct MessageRow: View {
    let item: MessageItem
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title)
                .foregroundStyle(Color.appTextTertiary(scheme))
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(Color.appTextPrimary(scheme))
                    if item.unread {
                        Circle().fill(Color.appPrimary(scheme)).frame(width: 8, height: 8)
                    }
                    Spacer()
                    Text(item.time)
                        .font(.caption2)
                        .foregroundStyle(Color.appTextTertiary(scheme))
                }
                Text(item.preview)
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary(scheme))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
    }
}
