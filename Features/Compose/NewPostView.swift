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
    @State private var message = "Peace&Love"

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
                    Button("发布") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
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
