import SwiftUI

/// 回帖占位符设置（我的 → 回帖占位符）。
///
/// 占位符是什么：4D4Y 所在 Discuz 有「回复最短字数」限制，占位符就是自动附带的凑字文本。
/// 本客户端约定（2026-09-19 起）：
/// 1. **不显示在输入框里** —— 输入框只放用户真正写的内容；
/// 2. 在输入框**下方**用最小字号斜体提示；
/// 3. 提交时**与正文隔一个空行**附加，作为发帖内容一起提交（发新帖同规则）。
/// 这里改的是第 3 步用的文本，改完立刻对回复框与发帖框生效（本地偏好，不改服务器数据）。
struct ReplyPlaceholderView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var prefs = PreferenceStore.shared

    @State private var draft: String = ""
    @State private var showSaved = false

    var body: some View {
        List {
            Section {
                // 输入框必须有可见边界：浅色下 List 行与页面同为白色，
                // 裸 TextField 会被当成静态文字（用户不知道可以改）。
                // 与回复框输入区同一口径：appSurfaceSecondary 填充 + 0.5pt appBorder 描边。
                TextField("占位符文本", text: $draft, axis: .vertical)
                    .foregroundStyle(Color.appTextPrimary(scheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.appSurfaceSecondary(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.appBorder(scheme), lineWidth: 0.5)
                    )
                    .onSubmit { commit() }
            } header: {
                Text("占位符")
            } footer: {
                Text("留空会自动回退为「\(PreferenceStore.defaultReplyPlaceholder)」。")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    // 输入框（示意）：只有用户写的内容
                    Text("这个我试过，确实如此")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextPrimary(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.appSurfaceSecondary(scheme))
                        .cornerRadius(10)

                    // 框外斜体提示（最小字号）
                    HStack(spacing: 4) {
                        Text("发布时自动附带（与回复正文隔一空行）")
                        Text(current).fontWeight(.medium)
                    }
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(Color.appTextTertiary(scheme))

                    Divider().background(Color.appDivider(scheme))

                    Text("实际提交内容")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary(scheme))
                    Text("这个我试过，确实如此\n\n\(current)")
                        .font(.footnote)
                        .foregroundStyle(Color.appTextPrimary(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.appSurfaceSecondary(scheme))
                        .cornerRadius(10)
                }
                .padding(.vertical, 4)
            } header: {
                Text("效果预览")
            } footer: {
                Text("占位符不会出现在输入框里，只在提交时附加。只回一个占位符（不写正文）时，提交内容就是占位符本身。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground(scheme))
        .navigationTitle("回帖占位符")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("恢复默认") {
                    draft = PreferenceStore.defaultReplyPlaceholder
                    commit()
                }
                .foregroundStyle(Color.appPrimary(scheme))
            }
        }
        .overlay(alignment: .bottom) {
            if showSaved {
                Text("已保存")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.appPrimary(scheme))
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .onAppear { draft = prefs.replyPlaceholder }
        .onDisappear { commit() }
    }

    /// 预览里用的当前值（跟着输入实时变，但空串不落到默认值上，避免预览跳动）。
    private var current: String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? PreferenceStore.defaultReplyPlaceholder : trimmed
    }

    private func commit() {
        let value = PreferenceStore.sanitizedPlaceholder(draft)
        draft = value
        guard prefs.replyPlaceholder != value else { return }
        prefs.replyPlaceholder = value
        withAnimation { showSaved = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation { showSaved = false }
        }
    }
}
