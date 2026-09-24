import Foundation

/// 「我的中心」读取失败的各种形态。
///
/// 与 `PMError` 同一套约定：**登录门 → 登录入口；读不出 → 如实说明**，
/// 绝不用空列表冒充「你没有内容」。
enum MySpaceError: LocalizedError, Equatable {
    /// 命中登录门：该页面必须登录才可读。
    case requiresLogin
    /// 导航解析成功、但本站的我的中心里**没有**这个栏目。
    /// （注意：这不是「关注」—— 关注是真实存在的，见 `MySpaceKind.isUserList` 的说明。）
    case sectionMissing(String)
    /// 页面拿到了但结构未识别（模板改版），明确告知而不是显示空列表。
    case unsupported
    case network(String)

    var errorDescription: String? {
        switch self {
        case .requiresLogin:
            return "「我的中心」需要登录：请先登录 4D4Y 账号。"
        case .sectionMissing(let name):
            return "本站（Discuz! 7.2）的「我的中心」里没有「\(name)」栏目，客户端不显示伪造内容。"
        case .unsupported:
            return "暂时读不出这个列表：论坛页面结构可能已变化。"
        case .network(let s):
            return "网络失败：\(s)"
        }
    }
}

protocol MySpaceRepositoryProtocol {
    /// 读取「我的中心」某个栏目。
    /// - Returns: `.success([])` 表示页面正常打开但没有内容（真正的空列表）。
    func entries(kind: MySpaceKind) async -> Result<[MySpaceEntry], MySpaceError>
}

/// 默认实现：先取 `my.php` **动态发现栏目参数**，再取目标栏目页做通用抽取。
///
/// 不硬编码 `item=` 参数的意义：站点换模板 / 改名时客户端自动跟随；
/// 站点没有这个栏目时能**准确区分**「没有」与「读不出来」。
final class MySpaceRepository: MySpaceRepositoryProtocol {

    private let client: HTTPClient

    init(client: HTTPClient = HTTPClient()) {
        self.client = client
    }

    func entries(kind: MySpaceKind) async -> Result<[MySpaceEntry], MySpaceError> {
        // 1) 先请求 my.php 本身：既判登录门，又从页内导航动态发现 item 参数。
        let rootHTML: String
        do {
            let request = try client.request(path: "my.php")
            rootHTML = try await client.sendText(request)
        } catch {
            return .failure(.network(Self.message(from: error)))
        }
        if PMListParser.isLoginGate(rootHTML) { return .failure(.requiresLogin) }

        let menu = MySpaceParser.menuItems(html: rootHTML)
        let resolved = kind.resolveItem(in: menu)
        // 导航被成功解析出来、但确实没有本栏目 → 本站不支持，如实说明。
        // ⚠️ 例外见 `hasExternalEntry`：站点可能把入口放在别的页面（「关注」就只出现在
        // 帖子页的 `favoritewin` 弹层里），此时不能凭「我的中心」导航缺项就下结论，
        // 仍按已知地址试一次，让真实页面结构说话。
        if resolved == nil, !menu.isEmpty, !kind.hasExternalEntry {
            return .failure(.sectionMissing(kind.title))
        }

        // 2) 取目标栏目页（优先动态发现到的参数，兜底候选）。
        let item = resolved ?? kind.fallbackItem
        let html: String
        do {
            let request = try client.request(path: "my.php?item=\(item)")
            html = try await client.sendText(request)
        } catch {
            return .failure(.network(Self.message(from: error)))
        }

        switch MySpaceParser.parse(html: html, kind: kind) {
        case .entries(let list): return .success(list)
        case .empty:             return .success([])
        case .requiresLogin:     return .failure(.requiresLogin)
        case .unsupported:       return .failure(.unsupported)
        }
    }

    private static func message(from error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
