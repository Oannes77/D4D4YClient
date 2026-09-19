import SwiftUI

/// 帖子详情页底部回复弹窗（引用式）。
/// 标题「我的回复」+ 输入框（默认填充占位符 Peace&Love，规避最短字数凑字）+ 回复按钮。
/// 默认隐藏，仅点「回复」才出现，不遮挡看帖。
struct ReplySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    let tid: Int
    let onSubmit: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    init(tid: Int, initial: String = "Peace&Love", onSubmit: @escaping (String) -> Void) {
        self.tid = tid
        self._text = State(initialValue: initial)
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

            // 多行大输入框：默认 6 行高度，内容超出时自动长高（最多 12 行），
            // 让用户直观看到自己输入的回复内容。
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("写回复…")
                        .foregroundStyle(Color.appTextTertiary(scheme))
                        .padding(.top, 8)
                        .padding(.leading, 6)
                }
                TextEditor(text: $text)
                    .frame(minHeight: 140, maxHeight: 280, alignment: .topLeading)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Color.appTextPrimary(scheme))
            }
            .frame(minHeight: 140, maxHeight: 280, alignment: .topLeading)
            .padding(4)
            .background(Color.appSurface(scheme))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.appDivider(scheme), lineWidth: 1)
            )
            .cornerRadius(10)

            Button {
                onSubmit(text)
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
        .presentationDetents([.fraction(0.6), .large])
        .presentationDragIndicator(.visible)
    }
}
