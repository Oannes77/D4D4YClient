import SwiftUI

/// 编辑自己的帖子（PC 模板 `post.php?action=edit…`）。
///
/// 只编辑**标题 + 正文**（站点的编辑页正是这两个字段：`subject` / `message`）。
/// 打开时先加载编辑页、把原文预填进来；保存走 `EditPostRepository`：
/// 运行时解析编辑表单 → GBK 表单 POST → **回读编辑页确认**。
///
/// 入口只出现在**你自己的楼层**（站点渲染了 `a.editpost`，即 `post.editPath != nil`）——
/// 站点不给入口就不会打开本页（绝不伪造一个点了没反应的编辑）。
struct EditPostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    /// 站点原样的编辑地址（来自楼层 `a.editpost` 的 href）。
    let editPath: String
    /// 保存成功后的回调（父视图据此刷新帖子）。
    var onSaved: () -> Void

    @State private var subject = ""
    @State private var message = ""
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isSaving = false
    @State private var notice: String?
    @State private var didSucceed = false

    init(editPath: String, onSaved: @escaping () -> Void) {
        self.editPath = editPath
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("加载编辑表单…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(Color.appTextSecondary(scheme))
                } else if let loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(Color.appWarning(scheme))
                        Text(loadError)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.appTextSecondary(scheme))
                        Button("重试") { Task { await load() } }
                            .foregroundStyle(Color.appPrimary(scheme))
                    }
                    .padding(24)
                } else {
                    form
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground(scheme))
            .navigationTitle("编辑帖子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView() } else { Text("保存").fontWeight(.semibold) }
                    }
                    .disabled(isSaving || isLoading || loadError != nil)
                }
            }
            .alert("编辑帖子", isPresented: Binding(
                get: { notice != nil },
                set: { if !$0 { notice = nil } }
            )) {
                Button("好", role: .cancel) {
                    let success = didSucceed
                    notice = nil
                    if success { dismiss() }
                }
            } message: {
                Text(notice ?? "")
            }
            .task { await load() }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("标题")
                    TextField("标题", text: $subject)
                        .padding(12)
                        .background(Color.appSurfaceSecondary(scheme))
                        .cornerRadius(10)
                        .foregroundStyle(Color.appTextPrimary(scheme))
                }

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("正文")
                    TextEditor(text: $message)
                        .frame(minHeight: 220)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.appSurfaceSecondary(scheme))
                        .cornerRadius(10)
                        .foregroundStyle(Color.appTextPrimary(scheme))
                }
            }
            .padding(16)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color.appTextSecondary(scheme))
    }

    /// 加载编辑页并预填原文（标题 + 正文）。
    private func load() async {
        isLoading = true
        loadError = nil
        let repo = EditPostRepository()
        switch await repo.loadEditForm(path: editPath) {
        case .success(let html):
            switch repo.parseEditForm(html) {
            case .success(let parsed):
                subject = parsed.subject
                message = parsed.messageText
            case .failure(let error):
                loadError = error.localizedDescription
            }
        case .failure(let error):
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func save() {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { notice = "正文不能为空"; return }
        guard !DemoMode.isOn else { notice = "演示模式：未真实提交"; return }
        isSaving = true
        Task {
            let result = await EditPostRepository().submitEdit(
                path: editPath,
                subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                message: trimmed
            )
            isSaving = false
            switch result {
            case .success:
                didSucceed = true
                onSaved()
                notice = "已保存"
            case .failure(let error):
                notice = error.localizedDescription
            }
        }
    }
}
