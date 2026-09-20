import Foundation
import SwiftSoup

/// 解析会员资料页 `space.php?uid=NNN`。
///
/// ⚠️ 结构未在本地验证（需登录态；游客实测返回登录门）。
/// 采用「标签→数值」的宽松抽取：只要页面上出现 Discuz 惯用的「积分 / 帖子 / 用户组」
/// 等标签，就能取到值；**取不到的字段一律为 nil，界面直接隐藏，绝不填示例数字**。
///
/// 用户名不由本页决定：调用方已经知道对方用户名（列表/楼层里就有），
/// 直接用 `fallbackName`，避免从模板标题里猜错名字。
struct ProfileParser {

    enum Outcome {
        case profile(UserProfile)
        case requiresLogin
        case unsupported
    }

    static func parse(html: String, uid: Int, fallbackName: String) -> Outcome {
        if PMListParser.isLoginGate(html) { return .requiresLogin }
        guard let doc = try? SwiftSoup.parse(html) else { return .unsupported }

        let text = (try? doc.text()) ?? ""

        let group = match(in: text, pattern: #"(?:用户组|会员组|分组|头衔|级别)\s*[:：]?\s*([^\s,，。；;|/、]{1,12})"#)
        let posts = match(in: text, pattern: #"(?:帖子|帖数|发帖)\s*[:：]?\s*(\d+)"#)
        let points = match(in: text, pattern: #"(?:积分|威望|金钱)\s*[:：]?\s*(\d+)"#)
        let registered = match(in: text, pattern: #"(?:注册时间|注册于|注册)\s*[:：]?\s*(\d{4}-\d{1,2}-\d{1,2})"#)
        let location = match(in: text, pattern: #"(?:来自|所在地|居住地)\s*[:：]?\s*([^\s,，。；;|/、]{1,16})"#)
        let signature = signatureText(from: doc)

        // 一个字段都取不到 → 结构未识别（避免显示一张全空、像是坏了的资料卡）
        guard group != nil || posts != nil || points != nil || registered != nil || signature != nil else {
            Log.parser.error("ProfileParser 未取到任何资料字段（结构未识别）uid=\(uid, privacy: .public)")
            return .unsupported
        }

        return .profile(UserProfile(
            uid: uid,
            name: fallbackName,
            group: group,
            posts: posts.flatMap { Int($0) },
            points: points.flatMap { Int($0) },
            signature: signature,
            registeredRaw: registered,
            location: location
        ))
    }

    /// 个性签名：Discuz 常见容器 class 含 sign / signature。
    private static func signatureText(from doc: Document) -> String? {
        let selectors = ["div[class*=sign]", "p[class*=sign]", "dd[class*=sign]", "div.signature"]
        for selector in selectors {
            guard let element = try? doc.select(selector).first() else { continue }
            let t = ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                return t.count > 60 ? String(t.prefix(60)) : t
            }
        }
        return nil
    }

    /// 取正则第 1 个捕获组。
    private static func match(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text,
                                            range: NSRange(text.startIndex..<text.endIndex, in: text)),
              result.numberOfRanges > 1,
              let range = Range(result.range(at: 1), in: text) else { return nil }
        let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
