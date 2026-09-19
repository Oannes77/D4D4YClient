import SwiftUI

/// 帖子详情页底部回复弹窗（引用式）。
/// 标题「我的回复」+ 多行大输入框 + 回复按钮。
///
/// 占位符（默认 Peace&Love，规避最短字数凑字）**不显示在输入框里**：
/// 在输入框下方用最小字号斜体展示提示，提交时自动附加到回复末尾，
/// 与用户真正输入的回复文字隔一个空行（Discuz 规则）。
struct ReplySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var text: String
    /// 自动附加的占位符（与回复正文隔行，作为发帖内容提交）。
    private let placeholder: String
    let tid: Int
    let onSubmit: (String) -> Void

    init(tid: Int,
         initial: String = "",
         placeholder: String = "Peace&Love",
         onSubmit: @escaping (String) -> Void) {
        self.tid = tid
        // initial 仅在「长按引用」时携带引用文本进输入框；默认为空，
        // 占位符不进输入框（见下方说明行）。
        self._text = State(initialValue: initial)
        self.placeholder = placeholder
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("我的回复")
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary(scheme))
                Spacer()
                Button("取消") { dismiss() }
                    .foregroundStyle(Color.appPrimary(scheme))
            }

            // 多行大输入框：默认约 7 行高度，内容超出时自动长高（最多 14 行）。
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("写回复…")
                        .foregroundStyle(Color.appTextTertiary(scheme))
                        .padding(.top, 8)
                        .padding(.leading, 6)
                }
                TextEditor(text: $text)
                    .frame(minHeight: 160, maxHeight: 320, alignment: .topLeading)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Color.appTextPrimary(scheme))
            }
            .frame(minHeight: 160, maxHeight: 320, alignment: .topLeading)
            .padding(4)
            .background(Color.appSurface(scheme))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.appDivider(scheme), lineWidth: 1)
            )
            .cornerRadius(10)

            // 占位符说明：最小字号 + 斜体，不进输入框；提交时自动附加并与正文隔行。
            HStack(spacing: 4) {
                Text("发布时自动附带（与回复正文隔一空行）")
                Text(placeholder).fontWeight(.medium)
            }
            .font(.caption2)
            .italic()
            .foregroundStyle(Color.appTextTertiary(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onSubmit(composedBody)
                dismiss()
            } label: {
                Text("回复")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.appPrimary(scheme))
                    .foregroundStyle(.white)
                    .cornerRadius(10)
            }
        }
        .padding(16)
        .presentationDetents([.fraction(0.62), .large])
        .presentationDragIndicator(.visible)
    }

    /// 提交内容 = 用户输入 + 空行 + 占位符（占位符始终存在，规避凑字规则）。
    private var composedBody: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? placeholder : "\(trimmed)\n\n\(placeholder)"
    }
}
