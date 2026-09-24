import SwiftUI
import SwiftData
import UIKit
import PhotosUI
import UniformTypeIdentifiers

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
    /// 当前板块的**主题分类**（站点每个板块不同，运行时从板块页解析，不硬编码）。
    @State private var categories: [BoardCategory] = []
    /// 分类**没读到**（登录门 / 网络 / 结构变化）。
    /// ⚠️ 必须与「该板块确实没有分类」区分开：读不到还默默不显示，就等于告诉用户「这个版没有分类」——
    /// 实测 Discovery（fid=2）与 Buy & Sell（fid=6）**游客一律是登录门**，本地根本读不到。
    @State private var categoriesUnavailable = false
    /// 选中的分类 `typeid`；该板块没有分类时为 nil（此时不显示分类选择，也不提交该字段）。
    @State private var selectedTypeID: Int?
    @State private var title = ""
    /// 正文从空开始；占位符不进输入框（见正文下方的斜体说明），发布时自动隔行附加。
    @State private var message = ""
    @State private var isPosting = false
    @State private var notice: String?
    @State private var postedTID: Int?
    @State private var didSucceed = false
    /// 待上传的附件（图片 / 其它文件）。提交时与正文一起 multipart 上传。
    @State private var attachments: [DraftAttachment] = []
    /// `PhotosPicker` 当前选中项。
    @State private var photoItems: [PhotosPickerItem] = []
    /// 是否展示系统「选择文件」。
    @State private var showFileImporter = false

    /// 单帖最多附件数（与界面提示保持一致）。
    static let maxAttachments = 5

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

    /// 已选分类名（未选为 nil）。
    private var selectedCategoryName: String? {
        guard let selectedTypeID else { return nil }
        return categories.first(where: { $0.id == selectedTypeID })?.name
    }

    // MARK: - 主题分类

    /// 拉取当前板块的主题分类。
    ///
    /// - 演示模式：从**离线夹具的真实板块页**解析（同一个解析器），不联网；夹具的 fid=14 才有分类，
    ///   其他板块按「没有分类」处理（不发假数据）。
    /// - 线上：`ForumRepository.categories(fid:)`。**读不到 ≠ 没有分类** —— 拉取失败时置
    ///   `categoriesUnavailable`，界面如实提示并给重试，绝不静默当成「这个版没有分类」。
    ///   （实测 Discovery fid=2、Buy & Sell fid=6 游客都是登录门；发帖时带登录态才会拿到真页面。）
    private func loadCategories() async {
        if DemoMode.isOn {
            categories = fid == 14 ? (DemoData.loadForumCategoryFixture() ?? []) : []
            categoriesUnavailable = false
        } else {
            do {
                categories = try await ForumRepository().categories(fid: fid)
                categoriesUnavailable = false
            } catch {
                Log.parser.error("主题分类读取失败(fid=\(fid, privacy: .public)): \(String(describing: error), privacy: .public)")
                categories = []
                categoriesUnavailable = true
            }
        }
        // 换板块后原来的 typeid 可能不属于新板块 —— 清掉，避免提交一个张冠李戴的分类。
        if let selectedTypeID, !categories.contains(where: { $0.id == selectedTypeID }) {
            self.selectedTypeID = nil
        }
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

                    // 主题分类（站点的 `typeid`）：**分类是发帖时贴给主题的标签**，
                    // 每个板块各不相同，所以换板块要重新解析一次；该板块没开分类就整块不显示。
                    if !categories.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("分类（该板块的主题分类）")
                            Menu {
                                ForEach(categories) { category in
                                    Button(category.name) { selectedTypeID = category.id }
                                }
                            } label: {
                                HStack {
                                    Text(selectedCategoryName ?? "请选择分类")
                                        .foregroundStyle(selectedCategoryName == nil
                                                         ? Color.appTextTertiary(scheme)
                                                         : Color.appTextPrimary(scheme))
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
                    } else if categoriesUnavailable {
                        // 读不到分类：如实说，并给重试。**不假装这个版没有分类。**
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("分类（该板块的主题分类）")
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(Color.appWarning(scheme))
                                Text("分类没读出来（可能未登录或网络问题）")
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextSecondary(scheme))
                                Spacer()
                                Button("重试") {
                                    Task { await loadCategories() }
                                }
                                .font(.caption)
                                .foregroundStyle(Color.appPrimary(scheme))
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

                    // 附件：图片走 PhotosPicker，其它文件走系统文件选择器。
                    // 提交时与正文一起以 multipart/form-data 一次性 POST（Discuz 发帖页本身即可带文件）。
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            PhotosPicker(selection: $photoItems,
                                         maxSelectionCount: Self.maxAttachments,
                                         matching: .images) {
                                attachLabel("photo", "图片")
                            }
                            Button { showFileImporter = true } label: {
                                attachLabel("paperclip", "附件")
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }

                        if !attachments.isEmpty {
                            attachmentStrip
                        }
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
            .onChange(of: photoItems) { _, items in
                Task { await loadPickedPhotos(items) }
            }
            // 换板块 ⇒ 重新解析该板块的主题分类（分类是按板块配的）。
            .task(id: fid) { await loadCategories() }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.item],
                          allowsMultipleSelection: true) { result in
                handleFileImport(result)
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
        // 附件转成数据层结构（正文与文件在同一次 multipart 请求里提交）。
        let payload = attachments.map {
            PostAttachment(fileName: $0.fileName, mimeType: $0.mimeType, data: $0.data)
        }
        Task {
            let result = await PostRepository().submitNewThread(
                fid: fid, subject: finalSubject, message: body, attachments: payload,
                typeID: selectedTypeID
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

    /// 附件按钮的**外观**：图片按钮包在 `PhotosPicker` 里、附件按钮包在 `Button` 里，
    /// 所以这里只返回外观，由调用方决定怎么包。
    private func attachLabel(_ icon: String, _ title: String) -> some View {
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

    /// 已选附件条（缩略图 + 单个移除）。
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(attachments) { item in
                    ZStack(alignment: .topTrailing) {
                        if let image = item.thumbnail {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.appSurfaceSecondary(scheme))
                                .frame(width: 72, height: 72)
                                .overlay {
                                    Image(systemName: "doc")
                                        .foregroundStyle(Color.appTextSecondary(scheme))
                                }
                        }

                        Button {
                            attachments.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(Color.appTextSecondary(scheme))
                                .background(Color.appBackground(scheme).clipShape(Circle()))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                }

                Text("共 \(attachments.count) / \(Self.maxAttachments) 个附件")
                    .font(.caption2)
                    .foregroundStyle(Color.appTextTertiary(scheme))
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - 附件读取

    /// 读取 PhotosPicker 选中的图片。
    private func loadPickedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var loaded: [DraftAttachment] = []
        for (index, item) in items.prefix(Self.maxAttachments).enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let type = item.supportedContentTypes.first
            let ext = type?.preferredFilenameExtension ?? "jpg"
            let mime = type?.preferredMIMEType ?? "image/jpeg"
            let stamp = UUID().uuidString.prefix(6)
            loaded.append(DraftAttachment(fileName: "photo-\(index + 1)-\(stamp).\(ext)",
                                          mimeType: mime,
                                          data: data,
                                          thumbnail: UIImage(data: data)))
        }
        attachments = Array(loaded.prefix(Self.maxAttachments))
    }

    /// 读取系统文件选择器选中的文件。
    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var loaded: [DraftAttachment] = []
        for url in urls.prefix(Self.maxAttachments) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            loaded.append(DraftAttachment(fileName: url.lastPathComponent,
                                          mimeType: Self.mimeType(for: url),
                                          data: data,
                                          thumbnail: UIImage(data: data)))
        }
        attachments = Array((attachments + loaded).prefix(Self.maxAttachments))
    }

    /// 按扩展名推断 MIME（Discuz 会据此决定是否当图片处理）。
    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "heic":        return "image/heic"
        case "webp":        return "image/webp"
        case "pdf":         return "application/pdf"
        case "zip":         return "application/zip"
        case "txt":         return "text/plain"
        default:            return "application/octet-stream"
        }
    }
}

/// 发帖页里待上传的一个附件（还没提交，仍在内存里）。
private struct DraftAttachment: Identifiable {
    let id = UUID()
    let fileName: String
    let mimeType: String
    let data: Data
    /// 图片缩略图；非图片为 nil（界面显示通用文件图标）。
    let thumbnail: UIImage?
}
