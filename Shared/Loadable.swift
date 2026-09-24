import Foundation

/// ViewModel 通用的加载状态。failed 区分面向用户的一句话与 Debug 详情。
enum Loadable<T> {
    case idle
    case loading
    case loaded(T)
    case failed(message: String, debugDetail: String)

    var value: T? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    /// 把底层错误翻译为用户可读信息 + Debug 详情。
    init(error: Error) {
        let message: String
        let detail: String
        switch error {
        case let e as NetworkError:
            message = e.errorDescription ?? "请求失败"
            if case .transport(let urlError) = e {
                detail = "URLError code=\(urlError.code.rawValue) \(urlError.localizedDescription)"
            } else if case .httpStatus(let code, let url) = e {
                detail = "HTTP \(code) @ \(url.absoluteString)"
            } else {
                detail = String(describing: e)
            }
        case let e as ThreadListParser.ListParseError:
            if case .siteAlert(let alert) = e {
                // 登录门 / 权限提示：显示**站点原文**，不要报「解析失败」——
                // 页面结构一点问题都没有，是这台访客没有权限（游客权限极低）。
                message = alert.reason ?? alert.message
                detail = "站点提示页（loginForm=\(alert.hasLoginForm)）"
            } else {
                message = "主题列表解析失败"
                detail = String(describing: e) + "（Selector 未匹配 / 列表为空）"
            }
        case let e as ThreadDetailParser.DetailParseError:
            if case .siteAlert(let alert) = e {
                message = alert.reason ?? alert.message
                detail = "站点提示页（loginForm=\(alert.hasLoginForm)）"
            } else {
                message = "帖子解析失败"
                detail = String(describing: e) + "（楼层节点为空 / 模板改版）"
            }
        default:
            message = "发生未知错误"
            detail = String(describing: error)
        }
        self = .failed(message: message, debugDetail: detail)
    }
}

extension Loadable {
    static func failed(_ error: Error) -> Loadable<T> {
        Loadable(error: error)
    }
}

// MARK: - Equatable
/// 按枚举 case 比较（不比较关联值），使 `onChange(of: viewModel.state)` 在 SwiftUI 中可用。
/// 仅用于感知「加载中 → 加载完成」等状态跃迁；关联值变化视为相等。
extension Loadable: Equatable {
    static func == (lhs: Loadable<T>, rhs: Loadable<T>) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):         return true
        case (.loading, .loading):   return true
        case (.loaded, .loaded):     return true
        case (.failed, .failed):     return true
        default:                     return false
        }
    }
}
