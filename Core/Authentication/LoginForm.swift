import Foundation

/// Discuz! 安全提问选项。
///
/// `id` 即表单字段 `questionid`；`id == 0` 表示"未设置安全提问"，此时无需填写答案。
struct SecurityQuestion: Identifiable, Hashable {
    let id: Int
    let text: String

    /// 是否需要填写答案（0 = 未设置安全提问）。
    var requiresAnswer: Bool { id != 0 }
}

extension SecurityQuestion {
    /// Discuz! 7.2 标准安全提问（登录页解析失败时的兜底列表）。
    ///
    /// 真实论坛可能定制过文案，因此优先使用从登录页实时解析出的选项；
    /// 仅在解析不到 `<select name="questionid">` 时才回退到这里。
    static let defaultList: [SecurityQuestion] = [
        SecurityQuestion(id: 0, text: "未设置安全提问"),
        SecurityQuestion(id: 1, text: "母亲的名字"),
        SecurityQuestion(id: 2, text: "爷爷的名字"),
        SecurityQuestion(id: 3, text: "父亲出生的城市"),
        SecurityQuestion(id: 4, text: "您其中一位老师的名字"),
        SecurityQuestion(id: 5, text: "您个人计算机的型号"),
        SecurityQuestion(id: 6, text: "您最喜欢的餐馆名称"),
        SecurityQuestion(id: 7, text: "驾驶执照的最后四位数字")
    ]
}

/// 登录页表单快照：一次 GET `logging.php?action=login` 后解析出的全部提交要素。
///
/// 之所以把表单单独成模型：Discuz 的 `formhash` 与 `sid` 绑定，
/// **必须先 GET 一次、再用同一次的隐藏字段 POST**，中途再 GET 会拿到新的 formhash。
struct LoginForm {
    /// 会话 ID（与 `cdb_sid` 一致），须原样回传。
    let sid: String
    /// CSRF / 防重放令牌。
    let formhash: String
    /// 登录后回跳地址（hidden，可空）。
    let referer: String
    /// 安全提问选项（解析失败时为标准兜底列表）。
    let questions: [SecurityQuestion]
    /// 服务端已注入图形验证码（seccode）→ 当前版本不支持，须明确报错且**不绕过**。
    let requiresCaptcha: Bool

    /// 默认选中的提问（未设置安全提问）。
    var defaultQuestionID: Int { questions.first?.id ?? 0 }
}
