import SwiftUI
import SwiftData

/// 发帖页（首页右下角紫色 FAB 唤起）。
///
/// Threads 极简风格：板块选择 → 标题（可选）→ 正文 → 发布。
/// 板块列表来自用户固定的板块（SwiftData `PinnedForum`），未配置时用内置常用板块。
/// 提交走 `PostRepository`：运行时解析 Discuz 发帖表单（formhash 等）后按 GBK 编码 POST。
struct NewPostView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \PinnedForum.sortOrder) private var pinned: [PinnedForum]

    /// 首页当前板块（作为默认发布板块）。
    let defaultFid: Int

    @State private var fid: Int
    @State private var title = ""
    /// 正文从空开始；占位符不进输入框（见正文下方的斜体说明），发布时自动隔行附加。
    @State private var message = ""
    @State private var isPosting = false
    @State private var notice: String?
    @State private var postedTID: Int?
    @State private var didSucceed = false

    /// 自动附加的占位符（规避最短字数凑字规则），与正文隔一个空行提交。
    /// 取值来自本地偏好（我的 → 回帖占位符），与回复框共用同一份设置。
    private var placeholder: String { prefs.replyPlaceholder }

    /// 本地偏好（占位符设置改动后这里立即跟着变）。
    @ObservedObject private var prefs = PreferenceStore.shared

    init(defaultFid: Int = 2) {
        self.defaultFid = defaultFid
        _fid = State(initialValue: defaultFid)
    }

    /// 可选板块：用户固定板块优先，否则内置常用板块。
    private var boards: [BoardChipItem] {
        let list = pinned.map { BoardChipItem(id: $0.fid, name: $0.name) }
        return list.isEmpty ? ForumBoards.defaults : list
    }

    private var currentBoardName: String {
        boards.first(where: { $0.id == fid })?.name ?? "板块 \(fid)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 板块选择
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("发布到")
                        Menu {
                            ForEach(boards) { board in
                                Button(board.name) { fid = board.id }
                            }
                        } label: {
                            HStack {
                                Text(currentBoardName)
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
                        fieldLabel("标题（可选，留空自动取正文首行）")
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

                    // 附件（Discuz 附件上传需 multipart 与附件 aid 流程，暂未接入）
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
                    Button {
                        publish()
                    } label: {
                        if isPosting { ProgressView() } else { Text("发布").fontWeight(.semibold) }
                    }
                    .disabled(isPosting)
                }
            }
            .alert("发帖", isPresented: Binding(
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
        }
    }

    // MARK: - 提交

    /// 提交内容 = 用户输入 + 空行 + 占位符（占位符始终存在，规避凑字规则）。
    private func publish() {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            notice = "正文不能为空"
            return
        }
        let body = "\(trimmed)\n\n\(placeholder)"
        let subject = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSubject = subject.isEmpty ? Self.autoTitle(from: trimmed) : subject

        // 演示模式：不发起任何真实请求
        guard !DemoMode.isOn else {
            notice = "演示模式：未真实提交（标题「\(finalSubject)」）"
            return
        }

        isPosting = true
        Task {
            let result = await PostRepository().submitNewThread(
                fid: fid, subject: finalSubject, message: body
            )
            isPosting = false
            switch result {
            case .success(let posted):
                postedTID = posted.tid
                didSucceed = true
                notice = posted.tid == nil ? "发布成功（服务端未返回帖子地址，请下拉首页刷新）" : "发布成功"
            case .failure(let error):
                notice = error.localizedDescription
            }
        }
    }

    /// 标题留空时取正文首行（最多 24 字），保证可在板块列表复查到。
    private static func autoTitle(from body: String) -> String {
        let firstLine = body.split(separator: "\n").first.map(String.init) ?? body
        return String(firstLine.prefix(24))
    }

    // MARK: - 组件

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color.appTextSecondary(scheme))
    }

    private func attachButton(_ icon: String, _ title: String) -> some View {
        Button {
            notice = "图片 / 附件上传尚未接入（Discuz 附件需 multipart 上传流程）"
        } label: {
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
