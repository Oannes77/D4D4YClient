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
            }
        }
    }

    // MARK: - 图片缩略图

    private var imagesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            ForEach(Array(images.enumerated()), id: \.offset) { pair in
                AsyncImage(url: pair.element) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(Color.appTextTertiary(scheme))
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .clipped()
                .onTapGesture { onImagesTap(images, pair.offset) }
            }
        }
    }

    // MARK: - HTML 图片处理（视图层，不触碰 Parser）

    /// 剔除 `<img ...>` 标签，避免 `NSAttributedString` 渲染出残缺 alt 文本与正文重复。
    static func stripImages(_ html: String) -> String {
        html.replacingOccurrences(of: #"<img[^>]*>"#,
                                  with: "",
                                  options: [.regularExpression, .caseInsensitive])
    }

    /// 从 HTML 中提取所有 `<img src="...">` 的地址，解析为绝对 URL。
    static func extractImageURLs(from html: String) -> [URL] {
        let pattern = #"<img[^>]+src=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match -> URL? in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: html) else {
                return nil
            }
            return Self.resolveURL(String(html[range]))
        }
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
