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

            TextField("写回复…", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 80, alignment: .topLeading)
                .foregroundStyle(Color.appTextPrimary(scheme))

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
        .presentationDetents([.fraction(0.45), .large])
        .presentationDragIndicator(.visible)
    }
}
