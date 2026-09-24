import XCTest

/// Codemagic 自动截图测试：演示模式下逐屏截取全部模块界面（亮 / 暗各一套）。
///
/// 方式：每个界面用启动参数 `-DemoScreen=<name>` 让 App **直接渲染该界面**
/// （路由见 `Shared/ScreenshotRoute.swift`），脚本只负责启动 + 等关键元素出现 + 截图。
/// 相比 XCUI 逐级点击，不再受动画 / 时序影响，一次 CI 就能出全套图。
///
/// 每个界面独立 launch / terminate，避免导航状态互相污染；单个界面缺失不阻断其余截图。
/// 每张截图作为 `XCTAttachment`（`lifetime = .keepAlways`）随 .xcresult 结果包产出，
/// 由 codemagic.yaml 通过 `xcrun xcresulttool export` 导出为 png 作为 artifact 收集。
final class AppScreenshotTests: XCTestCase {

    private struct Target {
        /// `ScreenshotScreen` 的 raw value（启动参数 `-DemoScreen=`）。
        let screen: String
        /// 截图前必须等待出现的关键元素（按钮文案 / identifier）。
        /// 固定 sleep 会撞上 App 启动过渡（此前偶发整屏纯黑截图），等元素出现可根治。
        let waitElement: String
        /// 元素出现后的额外稳定时间。
        let settle: TimeInterval
        /// 可选：截图前把该 identifier 的元素**滚进可视区**。
        /// 用于长首帖下方的操作栏这类「存在但在首屏之外」的元素 —— 不滚就只能拍到帖子正文。
        let scrollToElement: String?
        /// 可选：滚进可视区后再**点它一下**（用于展开 Menu，例如「分享」的两个选项）。
        let tapElement: String?
        /// 可选：点开后等待出现的文案，确认菜单真的展开了。
        let tapWaitText: String?
        /// 可选：截图前**先下拉一次**。
        /// 用于「默认收起、下拉才出现」的界面（首页的搜索+发帖那一行）——
        /// 不下拉的话那一行永远是收起的，截图什么也证明不了。
        let pullDown: Bool
        /// 可选：附件名后缀。同一界面需要拍多张不同状态时用来区分（默认用 `screen`）。
        let name: String?

        init(screen: String,
             waitElement: String,
             settle: TimeInterval,
             scrollToElement: String? = nil,
             tapElement: String? = nil,
             tapWaitText: String? = nil,
             pullDown: Bool = false,
             name: String? = nil) {
            self.screen = screen
            self.waitElement = waitElement
            self.settle = settle
            self.scrollToElement = scrollToElement
            self.tapElement = tapElement
            self.tapWaitText = tapWaitText
            self.pullDown = pullDown
            self.name = name
        }
    }

    /// 待验收界面清单（已确认的界面不再重复截图，节省 CI 时间）。
    /// 新增/修改界面时只需在此增删一行；回归全量时把下方 `confirmedTargets` 合并进来即可。
    private let targets = [
        // Sprint 16 本轮改动：
        // ① 首页：被拉黑作者的主题显示「-已拉黑-」占位
        //    （Demo 流把被拉黑的作者放在第 2 条，确保占位落在首屏内 —— 第 1 条带大图很高）
        Target(screen: "home",         waitElement: "home-post-open", settle: 1.2),
        // ①b 首页顶部那一行（搜索 + 发帖）**默认是收起的**，必须下拉一次才看得见 ——
        //    否则截图里永远是空的，等于没验。下拉后应看到「🔍 搜索 Discovery … [发帖]」一整排。
        Target(screen: "home",         waitElement: "home-post-open", settle: 1.0,
               pullDown: true, name: "homeSearchCompose"),
        // ①c 站点登录门（游客权限）：4D4Y 游客只读得了少数版块，受限版块（实测 Discovery /
        //    Buy & Sell）服务器直接返回「您还未登录，无权访问该版块」提示页。
        //    必须拍到「该版块需要登录 + 登录按钮 + 站点原文」，而不是空列表或「暂无主题」。
        //    这一步同时是「不撒谎」的自证：锚点等的是**登录按钮**，它出现才说明识别对了。
        Target(screen: "boardLoginGate", waitElement: "board-notice-login", settle: 1.2),
        // ② 详情页操作栏：分享改为菜单（系统分享 / 分享给好友）+ 「举报」+ 新增「关注主题」铃铛
        //    首帖正文很长，操作栏在首屏之外 —— 先滚进可视区，否则只能拍到正文，验收点根本看不到。
        Target(screen: "thread",       waitElement: "detail-reply",   settle: 0.6,
               scrollToElement: "post-share"),
        // ②b 同一界面再拍一张：点开「分享」菜单，确认两个选项都在（系统分享 / 分享给好友）
        Target(screen: "thread",       waitElement: "detail-reply",   settle: 0.6,
               scrollToElement: "post-share", tapElement: "post-share",
               tapWaitText: "分享给好友", name: "threadShareMenu"),
        // ②c 详情页图片：Sprint 18 最核心的用户可见成果（全局切桌面 UA / PC 模板后，正文图与附件图才拿得到）。
        //    用真实带图主题（tid=439576，首帖 5 张附件图，全部托管在 img02.4d4y.com）。
        //    图片网格在长正文下方、首屏之外，所以先滚到操作栏 —— 网格就贴在它上方，必然入镜。
        //    settle 给足 2.5s：5 张远程图要真的下载完，否则拍到的是加载占位。
        Target(screen: "threadImages", waitElement: "detail-reply",   settle: 2.5,
               scrollToElement: "post-share"),
        // ②d 附件区：**必须单独拍**。实测这些帖的文件型附件都在靠后的楼层
        //    （439576 → 第 3 / 9 楼，193033 → 第 11 / 13 楼），
        //    滚到「操作栏」只会拍到首帖，附件区根本不在画面里。
        //    这里改成滚到附件行本身（`post-attachment`）再拍。
        Target(screen: "threadImages", waitElement: "detail-reply",   settle: 2.0,
               scrollToElement: "post-attachment", name: "threadAttachments"),
        // ③ 用户卡：加好友 / 搜贴 / 拉黑 三键真实化（不再是空按钮）
        Target(screen: "userCard",     waitElement: "加好友",          settle: 1.2),
        // ④ 发帖页：图片 / 附件选择与预览条
        Target(screen: "newPost",      waitElement: "发布",            settle: 1.2),
        // ⑤ 我的收藏：改为论坛服务器收藏列表
        Target(screen: "savedThreads", waitElement: "我的收藏",        settle: 1.2),
        // ⑥ 上一轮改动、尚未验收：回帖占位符输入框补可见边界
        Target(screen: "replyPlaceholder", waitElement: "效果预览",     settle: 1.0),
        // ⑦ 举报私信：收件人 = 管理员 4D4Y（UID 29），输入框预填帖子链接草稿
        // 锚点必须与导航标题（`userName`）大小写一致，否则 XCUI 精确匹配不上、白白多等 12s。
        Target(screen: "reportChat",   waitElement: "4D4Y",          settle: 1.2),
        // ⑧ 我的 → 关注：口径已更正（`attention` 关注的是**主题**，参数 tid），
        //    这里必须看到真实的主题列表，而不是此前那句「本站没有这个栏目」。
        Target(screen: "myFollows",    waitElement: "my-space-row",  settle: 1.2),
    ]

    /// 已验收通过的界面（默认不跑）。需要全量回归时，把这组拼到 `targets` 后面即可。
    private let confirmedTargets = [
        // 2026-09-20 验收通过：我的中心四栏 + 消息推送
        Target(screen: "myThreads",     waitElement: "我的帖子",  settle: 1.2),
        Target(screen: "myFriends",     waitElement: "好友",     settle: 1.2),
        Target(screen: "myFollows",     waitElement: "关注",     settle: 1.2),
        Target(screen: "pushSettings",  waitElement: "上次检查", settle: 1.0),
        Target(screen: "home",          waitElement: "home-post-open",    settle: 1.2),
        Target(screen: "search",        waitElement: "home-post-open",    settle: 1.2),
        Target(screen: "imageViewer",   waitElement: "",                  settle: 1.0),
        Target(screen: "profile",       waitElement: "主题外观",           settle: 1.2),
        Target(screen: "savedThreads",  waitElement: "我的收藏",           settle: 1.0),
        Target(screen: "thread",        waitElement: "detail-reply",      settle: 2.0),
        Target(screen: "threadReplies", waitElement: "detail-page-prev",  settle: 2.5),
        Target(screen: "reply",         waitElement: "取消",               settle: 1.5),
        Target(screen: "userCard",      waitElement: "加好友",             settle: 1.5),
        Target(screen: "newPost",       waitElement: "发布",               settle: 1.0),
        Target(screen: "message",       waitElement: "消息",               settle: 1.2),
        Target(screen: "chat",          waitElement: "发送",               settle: 1.0),
        Target(screen: "boardManage",   waitElement: "添加",               settle: 1.0),
        Target(screen: "blockedUsers",  waitElement: "黑名单",             settle: 1.0),
        Target(screen: "settings",      waitElement: "主题外观",            settle: 1.0),
        Target(screen: "security",      waitElement: "退出登录",            settle: 1.0),
        Target(screen: "login",         waitElement: "登录",               settle: 1.0),
    ]

    /// 本次实际跑的界面。默认只跑待验收的 `targets`；
    /// Codemagic 里把环境变量 `SCREENSHOT_FULL=1` 打开即可全量回归（含已验收界面），无需改代码。
    private var activeTargets: [Target] {
        ProcessInfo.processInfo.environment["SCREENSHOT_FULL"] == "1"
            ? targets + confirmedTargets
            : targets
    }

    override func setUpWithError() throws {
        // 尽量多截几张：单个界面缺失不阻断其余截图。
        continueAfterFailure = true
    }

    func testLightScreenshots() { runScreenshots(dark: false) }
    func testDarkScreenshots() { runScreenshots(dark: true) }

    private func runScreenshots(dark: Bool) {
        for target in activeTargets {
            let app = XCUIApplication()
            app.launchArguments = ["-DemoMode", "-DemoScreen=\(target.screen)"]
            if dark { app.launchArguments.append("-DarkMode") }

            if app.state == .runningForeground { app.terminate() }
            app.launch()

            if app.state != .runningForeground {
                // 首启偶发不在前台（模拟器刚 boot 完 / 上一轮 terminate 未落定）：重试一次再判定。
                print("[Screenshots] 提示: \(target.screen) 首次启动未到前台 state=\(app.state.rawValue)，重试一次")
                app.launch()
                Thread.sleep(forTimeInterval: 2)
            }

            guard app.state == .runningForeground else {
                // 打印具体状态：0=unknown / 1=notRunning / 2=runningBackground / 3=runningForeground / 4=suspended。
                print("[Screenshots] 失败: \(target.screen) 启动后仍不在前台 state=\(app.state.rawValue)")
                XCTFail("截图前 App 已不在前台: \(target.screen)")
                continue
            }

            // 等关键元素出现，确认界面真正渲染完成。
            waitForAnchor(app, target)

            // 「默认收起、下拉才出现」的界面：先下拉一次再截。
            if target.pullDown {
                app.swipeDown()
                Thread.sleep(forTimeInterval: 0.6)
            }

            // 需要验收的元素若在首屏之外（例如长首帖下方的操作栏），先滚进可视区再拍。
            if let id = target.scrollToElement {
                scrollIntoView(app, id)
            }
            // 菜单类元素（分享 Menu）需要点开才能拍到选项。
            if let id = target.tapElement {
                expandMenu(app, id, expecting: target.tapWaitText)
            }
            Thread.sleep(forTimeInterval: target.settle)

            let screenshot = app.screenshot()
            // Xcode 16 的 XCUIScreenshot.pngRepresentation 返回非可选 Data，直接取值。
            let pngData = screenshot.pngRepresentation
            // 强制 public.png，避免默认输出 HEIC 导致 xcresulttool export 后 find *.png 得到 0 张。
            let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
            attachment.name = "\(dark ? "dark" : "light")-\(target.name ?? target.screen)"
            attachment.lifetime = .keepAlways
            add(attachment)

            app.terminate()
        }
    }

    /// 按 identifier 找元素。
    ///
    /// 先试 `buttons`（多数是按钮），再退到「任意类型的后代」——
    /// SwiftUI 的 `Menu` 在 XCUI 里不一定归类成 button，只按 buttons 找会漏掉。
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let button = app.buttons[identifier].firstMatch
        if button.exists { return button }
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// 把指定 identifier 的元素滚进可视区。
    ///
    /// 用 **`isHittable`（真的露出来且能点）** 作为判据，而不是固定滑动次数：
    /// 首帖正文长短不一，固定次数要么滑不够（还是拍不到），要么滑过头（把操作栏顶出屏幕）。
    /// 需要滚进可视区后重新判定的注释见 `scrollIntoView`：上限从 6 提到 15。
    /// 原因（2026-09-24 Sprint 20）：详情页改成「图片一张一行」后，首帖本身就有一屏多高；
    /// 6 次滑动常常够不到首帖下方的操作栏（浅色那两张干脆停在图片顶上没动），
    /// 于是「等到了但没拍到」——正是截断验收点的老毛病。上限提高不影响正常情况（命中即停）。
    private func scrollIntoView(_ app: XCUIApplication, _ identifier: String, maxSwipes: Int = 15) {
        for _ in 0..<maxSwipes {
            let el = element(app, identifier)
            if el.exists && el.isHittable { return }
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.35)
        }
        print("[Screenshots] 警告: 未能把 \(identifier) 滚进可视区（仍按当前画面截图）")
    }

    /// 点开菜单类元素并等它的选项出现，这样截图才能拍到展开后的菜单。
    private func expandMenu(_ app: XCUIApplication, _ identifier: String, expecting text: String?) {
        let el = element(app, identifier)
        guard el.exists && el.isHittable else {
            print("[Screenshots] 警告: \(identifier) 不可点击，跳过展开")
            return
        }
        el.tap()
        guard let text else {
            Thread.sleep(forTimeInterval: 0.8)
            return
        }
        let item = app.buttons[text].firstMatch
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if item.exists { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        print("[Screenshots] 警告: 点开 \(identifier) 后未见「\(text)」")
    }

    /// 等待关键元素出现，最多 12 秒。
    ///
    /// 同时盯「按钮」与「静态文本」两类元素：导航栏标题是静态文本，页内动作是按钮，
    /// 原先「先试按钮 12s、再试文本 3s」在最坏情况下要多花一个超时周期；
    /// 改为轮询后，标题类锚点（我的帖子 / 好友 / 关注 …）几乎立即命中。
    ///
    /// 注意：本方法**不再**负责 settle 停顿 —— 停顿统一放在 `runScreenshots` 里，
    /// 因为「滚动 / 展开菜单」也发生在等待之后、截图之前（否则会多停一次，白白拉长 CI）。
    private func waitForAnchor(_ app: XCUIApplication, _ target: Target) {
        guard !target.waitElement.isEmpty else { return }
        let text = target.waitElement
        let button = app.buttons[text].firstMatch
        let staticText = app.staticTexts[text].firstMatch

        let deadline = Date().addingTimeInterval(12)
        var found = false
        while Date() < deadline {
            if button.exists || staticText.exists { found = true; break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        if !found {
            print("[Screenshots] 警告: \(target.screen) 等待元素 \(text) 超时，仍按 current 画面截图")
        }
    }
}
