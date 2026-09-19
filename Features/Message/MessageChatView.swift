import SwiftUI

/// 私信会话（消息 → 站内短信 → 选一个联系人）。
///
/// Threads 极简气泡：对方消息靠左灰底，自己的消息靠右紫色；底部输入框常驻。
struct MessageChatView: View {
    let withUser: String

    @Environment(\.colorScheme) private var scheme
    /// 私信不使用占位符：输入框初始为空，仅保留系统提示「发消息…」。
    @State private var draft = ""

    private struct ChatLine: Identifiable {
        let id = UUID()
        let text: String
        let isMe: Bool
        let time: String
    }

    private let lines: [ChatLine] = [
        ChatLine(text: "老橡树：你那台 X1C 的进料轮换了吗？", isMe: false, time: "昨天 21:04"),
        ChatLine(text: "换了第三方硅胶轮，异响基本没了。", isMe: true, time: "昨天 21:10"),
        ChatLine(text: "太好了，我也下单一个，扭矩按多少拧？", isMe: false, time: "昨天 21:12"),
        ChatLine(text: "手感紧就行，别超过 0.4N·m，塑料件容易滑丝。", isMe: true, time: "昨天 21:15"),
        ChatLine(text: "收到，谢啦！", isMe: false, time: "今天 09:02"),
    ]

    init(with user: String = "老橡树") {
        self.withUser = user
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(lines) { line in
                        bubble(line)
                    }
                }
                .padding(16)
            }

            Divider().background(Color.appDivider(scheme))

            // 底部输入区
            HStack(alignment: .bottom, spacing: 10) {
                TextField("发消息…", text: $draft, axis: .vertical)
                    .padding(10)
                    .background(Color.appSurfaceSecondary(scheme))
                    .cornerRadius(18)
                    .foregroundStyle(Color.appTextPrimary(scheme))

                Button("发送") { draft = "" }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appPrimary(scheme))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.appBackground(scheme))
        }
        .background(Color.appBackground(scheme))
        .navigationTitle(withUser)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bubble(_ line: ChatLine) -> some View {
        HStack {
            if line.isMe { Spacer(minLength: 48) }
            VStack(alignment: line.isMe ? .trailing : .leading, spacing: 4) {
                Text(line.text)
                    .font(.subheadline)
                    .foregroundStyle(line.isMe ? .white : Color.appTextPrimary(scheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        line.isMe
                            ? Color.appPrimary(scheme)
                            : Color.appSurfaceSecondary(scheme)
                    )
                    .cornerRadius(16)
                Text(line.time)
                    .font(.caption2)
                    .foregroundStyle(Color.appTextTertiary(scheme))
            }
            if !line.isMe { Spacer(minLength: 48) }
        }
    }
}
