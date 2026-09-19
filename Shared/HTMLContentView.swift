import SwiftUI
import UIKit
import SwiftData

/// 把 Discuz! 帖子正文 HTML 渲染为原生界面。
///
/// Sprint 8 改进（解决「HTML 颜色覆盖 Theme」问题）：
/// 1. 注入随 `colorScheme` 切换的 CSS：透明背景、主题文字色、品牌紫链接色、图片自适应宽度。
/// 2. 渲染后遍历属性串，把整段前景色重写为主题文字色（链接保留品牌紫），
///    使论坛自带的 `<font color>` / 行内样式不再压过 App 主题。
/// 3. 字号 / 行距取自本地 `LocalSettings`（与「阅读设置」联动），并保留 HTML 的加粗等 emphasis。
///
/// SwiftUI 层不接触 HTML selector —— 本组件只接收 Parser 已提取好的 htmlContent。
struct HTMLContentView: View {
    let html: String
    /// 演示模式下是否同步渲染。仅用于首帖等关键视图，避免大量同步渲染导致主线程卡顿。
    let syncWhenDemo: Bool

    @Environment(\.colorScheme) private var scheme
    @Query private var settings: [LocalSettings]

    @State private var attributed: NSAttributedString?
    @State private var plainDemo: String = ""

    /// 正文基准字号（px），来自阅读设置；缺省 17。
    private var fontSize: CGFloat {
        CGFloat(settings.first?.fontSize ?? 17)
    }
    /// 行距系数（1.35 紧凑 / 1.5 标准 / 1.7 宽松），来自阅读设置；缺省 1.5。
    private var lineFactor: CGFloat {
        CGFloat(settings.first?.lineSpacing ?? 1.5)
    }

    init(html: String, syncWhenDemo: Bool = false) {
        self.html = html
        self.syncWhenDemo = syncWhenDemo
        // 演示模式：改用 SwiftUI Text 渲染纯文本（见 body），高度由文本测量在首帧同步确定，
        // 从根本上消除 UITextView 内容高度懒计算导致的 ScrollView 初始位置漂移。
        _plainDemo = State(initialValue: DemoMode.isOn ? Self.plainText(from: html) : "")
    }

    var body: some View {
        Group {
            if DemoMode.isOn {
                // 演示模式：SwiftUI Text 渲染纯文本，高度首帧即确定，
                // 配合 ThreadDetailView 的 ScrollView + .defaultScrollAnchor(.top)，
                // 首帖头部必然显示在顶部，不会被超长正文推出屏幕。
                Text(plainDemo)
                    .font(.system(size: fontSize))
                    .lineSpacing(fontSize * (lineFactor - 1.0))
                    .foregroundStyle(Color.appTextPrimary(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let attributed {
                AttributedTextView(attributed: attributed)
                    .frame(minHeight: 44)
            } else {
                ProgressView()
                    .frame(minHeight: 44)
            }
        }
        .task(id: html) {
            // 演示模式已在 init 就绪纯文本；非演示模式走后台异步 HTML 渲染。
            guard !DemoMode.isOn else { return }
            attributed = await Self.render(html: html, fontSize: fontSize, lineFactor: lineFactor, scheme: scheme)
        }
    }

    /// 把 HTML 正文粗略转成纯文本（演示模式用：去掉标签与常见 HTML 实体）。
    private static func plainText(from html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    /// UIKit 的 HTML 导入较慢，放在后台线程执行。
    private static func render(html: String, fontSize: CGFloat, lineFactor: CGFloat, scheme: ColorScheme) async -> NSAttributedString? {
        await Task.detached(priority: .userInitiated) {
            Self.renderSync(html: html, fontSize: fontSize, lineFactor: lineFactor, scheme: scheme)
        }.value
    }

    /// 同步渲染：用于 Demo 模式或数据量可控的场景。
    private static func renderSync(html: String, fontSize: CGFloat, lineFactor: CGFloat, scheme: ColorScheme) -> NSAttributedString? {
        // 与 AppTheme 真值对齐的文字 / 链接色（Light / Dark 自动切换）。
        let textHex: UInt32 = scheme == .dark ? 0xFFFFFF : 0x1C1C1E
        let linkHex: UInt32 = scheme == .dark ? 0xB69AE8 : 0x9B8BD4
        let textUIColor = UIColor(hex: textHex)
        let linkUIColor = UIColor(hex: linkHex)

        let css = """
        <style>
        body { font-family: -apple-system; font-size: \(Int(fontSize))px; \
        color: #\(String(format: "%06X", textHex)); background: transparent; margin: 0; padding: 0; }
        a { color: #\(String(format: "%06X", linkHex)); }
        img { max-width: 100%; height: auto; }
        </style>
        """
        let wrapped = "<html><head>\(css)</head><body>\(html)</body></html>"

        guard let data = wrapped.data(using: .utf8) else { return nil }
        guard let base = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        ) else { return nil }

        let mutable = NSMutableAttributedString(attributedString: base)
        let full = NSRange(location: 0, length: mutable.length)
        let extraLine = fontSize * (lineFactor - 1.0)   // 由系数换算为绝对行间距

        mutable.enumerateAttributes(in: full) { attrs, range, _ in
            // 前景色：链接保留品牌紫，其余统一为主题文字色（覆盖行内 color）。
            if attrs[.link] != nil {
                mutable.addAttribute(.foregroundColor, value: linkUIColor, range: range)
            } else {
                mutable.addAttribute(.foregroundColor, value: textUIColor, range: range)
            }
            // 行距：保留已有段落样式并叠加换算后的行间距。
            let para = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            para.lineSpacing = extraLine
            para.paragraphSpacing = extraLine * 0.5
            mutable.addAttribute(.paragraphStyle, value: para, range: range)
            // 字号：统一基准字号，但保留 HTML 的加粗 emphasis。
            let isBold = (attrs[.font] as? UIFont)?
                .fontDescriptor.symbolicTraits.contains(.traitBold) ?? false
            let font: UIFont = isBold
                ? UIFont.boldSystemFont(ofSize: fontSize)
                : UIFont.systemFont(ofSize: fontSize)
            mutable.addAttribute(.font, value: font, range: range)
        }
        return mutable
    }
}

private struct AttributedTextView: UIViewRepresentable {
    let attributed: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.backgroundColor = .clear
        view.adjustsFontForContentSizeCategory = true
        view.linkTextAttributes = [.underlineStyle: NSUnderlineStyle.single.rawValue]
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = attributed
    }
}
