import Foundation

/// 站点的「提示信息」页（Discuz `div.fcontent.alert_win`）。
///
/// 为什么必须单独建模：4D4Y 的**游客权限极低**（用户 2026-09-24 明确口径：
/// 「游客只能浏览除这两个版块之外的其他版块，其他任何功能都需要登录」）。
/// 实测（桌面 UA、游客、`forumdisplay.php?fid=2`）服务器返回的是 7 KB 的提示页：
///
/// ```html
/// <div class="fcontent alert_win">
///   <h3 class="float_ctrl"><em>4D4Y 提示信息</em></h3>
///   <div class="postbox"><div class="alert_error">
///     <p>您无权进行当前操作，原因如下：</p>
///     <p>对不起，您还未登录，无权访问该版块。</p>
///   </div>
///   <div class="alert_act">
///     <form method="post" name="login" id="loginform" class="gateform"
///           action="logging.php?action=login&amp;loginsubmit=yes">
/// ```
///
/// 这页**没有主题行、也没有楼层锚点**，所以老代码一路走到「列表为空」⇒ 界面说
/// 「该板块暂无主题」。**那是撒谎**：不是没有主题，是你没登录。
/// 所以这一层要把它和「解析失败」「真的没有内容」严格区分开。
struct SiteAlert: Equatable {
    /// 页面提示的完整原文（多段用空格连接），直接可显示，客户端不自己编文案。
    let message: String
    /// 最具体的那一段（站点把「原因」写在最后一段），例如
    /// `对不起，您还未登录，无权访问该版块。`
    let reason: String?
    /// 页面里是否带登录表单（`form#loginform` / `logging.php?action=login`）。
    ///
    /// 它同时是「登录能不能解决问题」的判据：游客被挡 ⇒ 带表单，登录即可；
    /// 已登录但权限不够 ⇒ Discuz 不给表单，此时界面**不该**再劝人登录。
    let hasLoginForm: Bool
}

/// 界面渲染用的站点提示（Error → UI 模型的收敛点，避免每个界面各写一遍判断）。
struct SiteNotice: Equatable {
    /// 显示用的一句话（取站点最具体的那段，拿不到才退回全文）。
    let message: String
    /// true = 给「登录」按钮；false = 只给「重试」（登录解决不了）。
    let needsLogin: Bool

    init(alert: SiteAlert) {
        message = alert.reason ?? alert.message
        needsLogin = alert.hasLoginForm
    }

    /// 供演示 / 截图路由直接构造（文案必须来自真实夹具解析，不手写）。
    init(message: String, needsLogin: Bool) {
        self.message = message
        self.needsLogin = needsLogin
    }
}
