import SwiftUI

/// 楼层正文。
///
/// 展示优先级：
/// 1. **本地拉黑**（用户自己在 `BlockedUser` 里拉黑了该作者）→ 显示「-已拉黑-」，
///    不渲染任何正文 / 图片，并提供「取消拉黑」出口。这是**用户自己的选择**，纯客户端行为。
/// 2. **论坛侧屏蔽**（`Post.isBlocked`，作者被禁言 / 帖子被删）→ 显示「该帖已被论坛隐藏」。
///    这是**论坛管理员的处罚**，客户端只能如实转述，不提供任何开关。
/// 3. 正常：HTML 正文（`HTMLContentView`）+ 提取出的图片缩略图（点击 → `onImagesTap` 全屏查看）。
///
/// ⚠️ 第 1 条和第 2 条是两件不同的事：数据源不同（`BlockedUser` vs `Post.isBlocked`）、
/// 文案不同、可否取消不同。**不要混用同一个标志或同一句话**。
///
/// 图片处理说明：
/// `HTMLContentView` 基于 `NSAttributedString` 导入，不会真正加载远程图片，
/// 故此处从 `htmlContent` 中正则提取 `<img src>` 单独以 `AsyncImage` 渲染，
/// 既补全图片展示，又避免与正文重复（正文侧已剔除 `<img>` 标签）。
/// 点任意一张进入全屏画廊，可左右滑动浏览**本楼层**的全部图片。
struct PostContent: View {
    let post: Post
    /// 是否已被**本地** `BlockedUser` 拉黑（由父视图基于 `post.authorID` 计算后传入）。
    /// 这是「用户自己的选择」，与下面的 `post.isBlocked`（论坛管理员处罚）不是一回事。
    let isBlocked: Bool
    /// 取消本地拉黑的回调（由父视图提供，写入 `BlockedUser`）。nil 时不显示取消按钮。
    let onUnblock: (() -> Void)?
    /// 点击图片缩略图时的回调：参数为「本楼层全部图片 + 被点的下标」，供全屏画廊左右滑浏览。
    let onImagesTap: ([URL], Int) -> Void
    /// 演示模式下是否同步渲染 HTML 正文。默认 false，仅首帖等关键视图传 true。
    let syncWhenDemo: Bool
    /// 正文里的图片（init 时算一次，避免 body 多次求值重复跑正则）。
    private let images: [URL]

    @Environment(\.colorScheme) private var scheme

    init(post: Post, isBlocked: Bool, onUnblock: (() -> Void)? = nil,
         onImagesTap: @escaping ([URL], Int) -> Void, syncWhenDemo: Bool = false) {
        self.post = post
        self.isBlocked = isBlocked
        self.onUnblock = onUnblock
        self.onImagesTap = onImagesTap
        self.syncWhenDemo = syncWhenDemo
        self.images = Self.extractImageURLs(from: post.htmlContent)
    }

    var body: some View {
        if isBlocked {
            // 本地拉黑（用户自己的选择）：显示「-已拉黑-」，并提供就地取消的出口。
            // 与下面的「该帖已被论坛隐藏」（管理员处罚，客户端无法改变）严格区分。
            HStack(spacing: 8) {
                Image(systemName: "nosign")
                Text("-已拉黑-")

                Spacer(minLength: 8)

                if let onUnblock {
                    Button("取消拉黑", action: onUnblock)
                        .foregroundStyle(Color.appPrimary(scheme))
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("unblock-user")
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.appTextTertiary(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else if post.isBlocked {
            // 论坛侧：管理员处罚（作者被禁言 / 帖子被删）。只能如实转述，不提供任何开关。
            HStack(spacing: 6) {
                Image(systemName: "eye.slash")
                Text("该帖已被论坛隐藏")
            }
            .font(.footnote)
            .foregroundStyle(Color.appTextTertiary(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HTMLContentView(html: Self.stripImages(post.htmlContent), syncWhenDemo: syncWhenDemo)

                if !images.isEmpty {
                    imagesGrid
                }

                if !post.attachments.isEmpty {
                    attachmentList
                }
            }
        }
    }

    // MARK: - 图片缩略图

    /// 楼层图片：**一张一行**，按原始比例铺满可用宽度。
    ///
    /// 2026-09-24 改：原先用 `LazyVGrid(.adaptive(minimum: 110))` 排成 120pt 高的方块墙
    /// （一行 3 张，`scaledToFill` 裁掉两边）。论坛附件多是竖拍照片或整屏截图，
    /// 裁成小方块后既看不清内容、一行里的宽窄高矮又不齐，观感很乱。
    /// 改成竖排后：每张图完整可见（`scaledToFit` 不裁切），点任意一张仍进全屏画廊左右滑。
    private var imagesGrid: some View {
        VStack(spacing: 8) {
            ForEach(Array(images.enumerated()), id: \.offset) { pair in
                AsyncImage(url: pair.element) { phase in
                    switch phase {
                    case .empty:
                        // 加载中给一块占位（不是零高度），避免图片到达时整页高度跳变。
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .background(Color.appSurfaceSecondary(scheme))
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                    case .failure:
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(Color.appTextTertiary(scheme))
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                            .background(Color.appSurfaceSecondary(scheme))
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture { onImagesTap(images, pair.offset) }
            }
        }
    }

    // MARK: - 文件型附件（zip / rar / pdf…）

    /// 附件区：列出文件名 + 体积 / 下载次数，右侧一键分享。
    ///
    /// **为什么只做「分享」不做「下载」**：iOS 上没有统一的「下载到哪」；
    /// 而系统分享面板本身就含「存储到文件 / 用浏览器打开 / 拷贝链接」三条真实出路，
    /// 所以这是**真能用的路径**，而不是拿一个假的进度条假装下载成功。
    /// 另外附件的实际下载在站点侧可能需要登录 —— 界面上如实提示一句，不含糊。
    private var attachmentList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                Text("附件 \(post.attachments.count) 个 · 下载需论坛登录")
            }
            .font(.footnote)
            .foregroundStyle(Color.appTextSecondary(scheme))

            ForEach(post.attachments) { file in
                HStack(spacing: 10) {
                    Image(systemName: Self.iconName(for: file.fileExtension))
                        .font(.title3)
                        .foregroundStyle(Color.appPrimary(scheme))
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.title)
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextPrimary(scheme))
                            .lineLimit(1)
                        if !file.detailText.isEmpty {
                            Text(file.detailText)
                                .font(.caption2)
                                .foregroundStyle(Color.appTextTertiary(scheme))
                        }
                    }

                    Spacer(minLength: 8)

                    if let url = HTTPClient.absoluteURL(path: file.url) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.subheadline)
                                .foregroundStyle(Color.appPrimary(scheme))
                                .padding(6)
                        }
                        .accessibilityLabel("分享附件 \(file.title)")
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.appSurfaceSecondary(scheme))
                .cornerRadius(10)
                // 截图锚点：附件可能在很靠后的楼层（实测 439576 在第 3 / 9 楼、193033 在第 11 / 13 楼），
                // 没有标识符就没法让截图脚本「滚到附件那一行再拍」。
                .accessibilityIdentifier("post-attachment")
            }
        }
    }

    /// 按扩展名挑一个系统图标（辨类型用，认不出就用通用文档图标，不猜）。
    static func iconName(for ext: String) -> String {
        switch ext {
        case "rar", "zip", "7z", "tar", "gz":     return "doc.zipper"
        case "pdf":                                return "doc.richtext"
        case "doc", "docx", "pages":               return "doc.text"
        case "xls", "xlsx", "csv":                 return "tablecells"
        case "ppt", "pptx", "key":                 return "rectangle.on.rectangle"
        case "txt", "md", "log":                   return "doc.plaintext"
        case "mp3", "wav", "m4a", "flac":          return "waveform"
        case "mp4", "mov", "avi", "mkv":           return "film"
        case "exe", "apk", "dmg", "ipa":           return "shippingbox"
        case "jpg", "jpeg", "png", "gif", "webp":  return "photo"
        default:                                   return "doc"
        }
    }

    // MARK: - HTML 图片处理（视图层，不触碰 Parser）

    /// 剔除 `<img ...>` 标签，避免 `NSAttributedString` 渲染出残缺 alt 文本与正文重复。
    static func stripImages(_ html: String) -> String {
        html.replacingOccurrences(of: #"<img[^>]*>"#,
                                  with: "",
                                  options: [.regularExpression, .caseInsensitive])
    }

    /// 从楼层正文 HTML 中提取所有内容图片，解析为绝对 URL。
    ///
    /// 直接复用 `ThreadImageParser`（**单一真相**）：它会优先取 `file` 属性
    /// （Discuz 附件图的真实地址写在 `file` 上，`src` 只是占位 `images/common/none.gif`），
    /// 并统一过滤头像 / 表情 / 图标 / 模板资源 —— 与列表首图的判定口径完全一致。
    static func extractImageURLs(from html: String) -> [URL] {
        ThreadImageParser.parseContentImageURLs(from: html)
    }

    /// 将（可能为相对/协议相对）的图片地址解析为绝对 URL。
    ///
    /// 未来优化②：此图片地址解析逻辑应抽离为独立 `ForumURLResolver`
    /// （统一相对 / 绝对 URL 补全、CDN 域名校准），供 ThreadList / ThreadDetail 复用。
    static func resolveURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        } else if trimmed.hasPrefix("//") {
            return URL(string: "https:" + trimmed)
        } else if trimmed.hasPrefix("/") {
            return URL(string: "https://www.4d4y.com" + trimmed)
        } else if !trimmed.isEmpty {
            return URL(string: "https://www.4d4y.com/" + trimmed)
        }
        return nil
    }
}
