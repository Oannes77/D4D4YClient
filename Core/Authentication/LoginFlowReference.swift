import Foundation

/// 登录流程参考元数据（Sprint 5A + 5B 探查产物）。
///
/// ⚠️ **REFERENCE ONLY** —— 本类型**不发起任何网络请求**，仅记录 Discuz! 7.2 登录流程的
/// 端点与字段名，供未来登录阶段（须用户明确授权、且不得绕过权限 / 验证码 / Cloudflare）实现时消费。
/// 当前构建中**未被任何模块引用**。
///
/// 实证结论与完整说明见 `docs/LoginFlowReal.md`（Sprint 5B，基于真实抓取）：
/// - 真实登录入口 = `logging.php?action=login`（实测 HTTP 200；标准 `login.php` 实测 404）。
/// - Cookie 前缀实测为 `cdb_`（GET 即下发 `cdb_sid`）。
/// - 核心鉴权 Cookie = `cdb_auth`（Discuz 7.2 无独立 `saltkey` Cookie，saltkey 内嵌于 `cdb_auth` 载荷）。
/// - 密码提交前由页面 `pwmd5()` 客户端 MD5，服务端收 `md5(rawpw)`。
enum LoginFlowReference {
    /// 论坛基址（已实证可达）。
    static let forumBaseURL = "https://www.4d4y.com/forum/"

    /// Discuz Cookie 表前缀（已实证：GET 登录页下发 `cdb_sid`）。
    /// 由此派生：`cdb_auth`（鉴权）、`cdb_sid`（会话）。
    static let cookiePrefix = "cdb_"

    // MARK: - 端点（Sprint 5B 实证）

    /// ✅ 真实登录入口（实测 GET → 200，返回登录表单）。
    static let realLoginPath = "logging.php?action=login"
    /// 完整登录 URL（GET 取表单用）。
    static let realLoginURL = forumBaseURL + realLoginPath
    /// 登录 POST 提交地址（表单 action 绝对化；含 `loginsubmit=yes` 查询参数）。
    static let realLoginSubmitURL = forumBaseURL + "logging.php?action=login&loginsubmit=yes"
    /// 退出登录（须先 GET 取 formhash）。
    static let logoutPath = "member.php?action=logout"

    // MARK: - 历史候选（Sprint 5A，4D4Y 实测不可用，保留备查）

    /// ⚠️ 标准 Discuz 7.2 登录脚本名；在 4D4Y 实测 404。
    static let standardLoginScript = "login.php"
    /// member 脚本名；存在但标准登录/登出动作未开放（返回「未定义操作」）。
    static let memberScript = "member.php"
    /// 注册（wap 定制为 tobenew.php，实测 register.php 404）。
    static let registerScript = "tobenew.php"

    // MARK: - 登录表单字段名（Sprint 5B 实证自真实 HTML）

    enum FormField {
        /// 会话 ID，与 `cdb_sid` 一致，须原样回传。
        static let sid = "sid"
        /// CSRF / 防重放令牌，每次 GET 重新生成，POST 必带。
        static let formhash = "formhash"
        /// 登录后回跳地址（hidden，可空）。
        static let referer = "referer"
        /// 登录标识类型：username / uid / email。
        static let loginfield = "loginfield"
        static let username = "username"
        /// 密码字段 name；⚠️ 提交前须客户端 MD5（页面 pwmd5() 复刻），元素 id=`password3`。
        static let password = "password"
        /// 安全提问：0=无，1–7=预设问题。
        static let questionid = "questionid"
        /// 安全提问答案（仅 questionid>0 时填）。
        static let answer = "answer"
        /// 记住登录状态（checkbox，勾选值 2592000 = 30 天）。
        static let cookietime = "cookietime"
        /// 登录判定开关（button name=loginsubmit value=true；action 查询串亦含 loginsubmit=yes）。
        static let loginsubmit = "loginsubmit"
        /// 验证码（⚠️ 条件出现：默认无，失败多次后服务端注入 `#seccodelayer`）。
        static let seccodeverify = "seccodeverify"
    }

    // MARK: - 关键 Cookie 名（Sprint 5B 实证）

    enum AuthCookie {
        /// ✅ 核心鉴权 Cookie（前缀 + "auth"）；持久凭证，**须存 Keychain，不入 SwiftData**。
        static let auth = "cdb_auth"
        /// 会话 ID（前缀 + "sid"）；GET 即下发，登录后延续。
        static let sid = "cdb_sid"
        /// ⚠️ Discuz 7.2 **无独立 saltkey Cookie**：saltkey 内嵌于 `cdb_auth` 加密载荷。
        /// （Discuz X 才有分离式 saltkey；此处仅作文档对照，不用于客户端存储。）
        static let saltkeyLegacyNote = "discuz7.2: no standalone saltkey cookie"
    }
}
