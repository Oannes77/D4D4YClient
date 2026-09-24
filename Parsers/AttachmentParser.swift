import Foundation
import SwiftSoup

/// 解析楼层里的**文件型附件**（zip / rar / pdf / txt…）。
///
/// 只认 PC 模板的 `div.postattachlist > dl.t_attachlist`，且**必须排除**带 `attachimg` class 的那些
/// —— 后者是图片附件，已经由正文图片网格渲染，再列一次会让同一张图出现两遍。
///
/// 观察到的两种形态（真实页面实测）：
/// - 图片：`<dl class="t_attachlist attachimg">` + `<p class="imgtitle">`  + `<img file="…">`
/// - 文件：`<dl class="t_attachlist">`       + `<p class="attachname">` + `<dt><img src="…/attachicons/rar.gif">`
///
/// 取不到的字段一律留空 / nil，**不编造**（页面没给体积就不显示体积）。
enum AttachmentParser {

    /// 从某个楼层的容器元素里抽附件。容器需要把 `div.postattachlist` 包在内（`ThreadDetailParser` 传的是楼容器）。
    static func parse(container: Element) -> [PostFileAttachment] {
        var result: [PostFileAttachment] = []
        let lists = (try? container.select("div.postattachlist dl.t_attachlist")) ?? Elements()
        for dl in lists {
            // 排除图片附件
            if let cls = try? dl.className(), cls.contains("attachimg") { continue }

            guard let anchor = (try? dl.select("p.attachname > a").first()) ?? nil
                    ?? (try? dl.select("dd a[href*=attachment.php]").first()) ?? nil else { continue }
            guard let href = try? anchor.attr("href"), !href.isEmpty else { continue }
            let title = ((try? anchor.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            // 体积：锚点之后的文本里形如 (309.58 KB)
            let attachNameText = ((try? dl.select("p.attachname").first()?.text()) ?? "")
            let sizeText = size(in: attachNameText)

            // 下载次数：弹层里的「下载次数:8115」
            var downloadCount: Int?
            let popupText = ((try? dl.select("div.attach_popup").first()?.text()) ?? "")
            if let range = popupText.range(of: #"下载次数[:：]\s*(\d+)"#, options: .regularExpression) {
                downloadCount = Int(popupText[range].filter { $0.isNumber })
            }

            // 地址原样保留（含签名 token —— 那是站点自己的凭据地址，不能改写），
            // 只剥掉 `sid` 会话参数：它属于「我这次会话」，分享给别人时既没用又会外泄会话 ID。
            let cleanURL = PaginationParser.strippingSessionID(
                href.replacingOccurrences(of: "&amp;", with: "&")
            )
            result.append(PostFileAttachment(
                url: cleanURL,
                title: title.isEmpty ? "附件" : title,
                sizeText: sizeText,
                downloadCount: downloadCount,
                fileExtension: (title as NSString).pathExtension.lowercased()
            ))
        }
        return result
    }

    /// 从 `iSilo.rar (309.58 KB)` 这样的文本里取出 `309.58 KB`。
    private static func size(in text: String) -> String {
        guard let range = text.range(of: #"\(\s*([\d.]+\s*[KMG]?B)\s*\)"#,
                                     options: [.regularExpression, .caseInsensitive]) else { return "" }
        return String(text[range])
            .trimmingCharacters(in: CharacterSet(charactersIn: "() "))
    }
}
