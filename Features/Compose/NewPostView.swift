import SwiftUI

/// 发帖页（首页右下角紫色 FAB 唤起）。
///
/// Threads 极简风格：板块选择 → 标题（可选）→ 正文 → 图片附件 → 发布。
/// 表单字段遵循 Discuz 发帖接口：fid / subject / message。
struct NewPostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var board = "Discovery"
    @State private var title = ""
    /// 正文从空开始；占位符不进输入框（见正文下方的斜体说明），发布时自动隔行附加。
    @State private var message = ""

    /// 自动附加的占位符（规避最短字数凑字规则），与正文隔一个空行提交。
    private let placeholder = "Peace&Love"

    private let boards = [
        "Discovery",
        "Buy & Sell 交易服务区",
        "Geek Talks 奇客怪谈",
        "Smartphone",
        "麦客爱苹果",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 板块选择
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("发布到")
                        Menu {
                            ForEach(boards, id: \.self) { name in
                                Button(name) { board = name }
                            }
                        } label: {
                            HStack {
                                Text(board)
                                    .foregroundStyle(Color.appTextPrimary(scheme))
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextTertiary(scheme))
                            }
                            .padding(12)
                            .background(Color.appSurfaceSecondary(scheme))
                            .cornerRadius(10)
                        }
                    }

                    // 标题（可选）
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("标题（可选）")
                        TextField("给帖子起个标题…", text: $title)
                            .padding(12)
                            .background(Color.appSurfaceSecondary(scheme))
                            .cornerRadius(10)
                            .foregroundStyle(Color.appTextPrimary(scheme))
                    }

                    // 正文
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("正文")
                        TextEditor(text: $message)
                            .frame(minHeight: 180)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color.appSurfaceSecondary(scheme))
                            .cornerRadius(10)
                            .foregroundStyle(Color.appTextPrimary(scheme))

                        // 占位符说明：最小字号 + 斜体，不进正文框；发布时自动隔行附加。
                        HStack(spacing: 4) {
                            Text("发布时自动附带（与正文隔一空行）")
                            Text(placeholder).fontWeight(.medium)
                        }
                        .font(.caption2)
                        .italic()
                        .foregroundStyle(Color.appTextTertiary(scheme))
                    }

                    // 附件
                    HStack(spacing: 16) {
                        attachButton("photo", "图片")
                        attachButton("paperclip", "附件")
                        Spacer()
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground(scheme))
            .navigationTitle("发布新帖")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发布") {
                        // 提交内容 = 用户输入 + 空行 + 占位符（占位符始终存在，规避凑字规则）。
                        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                        let body = trimmed.isEmpty ? placeholder : "\(trimmed)\n\n\(placeholder)"
                        submit(board: board, title: title, message: body)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    /// 提交发帖（真实模式接 Discuz post 接口；当前为演示占位）。
    private func submit(board: String, title: String, message: String) {
        // TODO: 接入 newthread.php / post.php 提交流程。
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color.appTextSecondary(scheme))
    }

    private func attachButton(_ icon: String, _ title: String) -> some View {
        Button { } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).font(.subheadline)
            }
            .foregroundStyle(Color.appPrimary(scheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.appSurfaceSecondary(scheme))
            .cornerRadius(10)
        }
    }
}
