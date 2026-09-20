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
    }

    /// 待验收界面清单（已确认的界面不再重复截图，节省 CI 时间）。
    /// 新增/修改界面时只需在此增删一行；回归全量时把下方 `confirmedTargets` 合并进来即可。
    private let targets = [
        // 帖子详情：操作栏改为 回复 / 分享 / 本地收藏 / 网页版 —— 四个都做真实的事。
        Target(screen: "thread",       waitElement: "detail-reply", settle: 2.0),
        // 图片全屏画廊：多图左右滑 + 顶部「n / N」页码。
        Target(screen: "imageViewer",  waitElement: "",             settle: 2.0),
        // 私信会话：发送按钮改为真实提交（Demo 下明确提示不实际发送）。
        Target(screen: "chat",         waitElement: "发送",          settle: 1.0),
        // 我的：宫格六个入口全部可点（收藏/黑名单进本地列表，其余给说明页 + 网页版出口）。
        Target(screen: "profile",      waitElement: "主题外观",       settle: 1.2),
        // 新增界面：我的收藏（本地书签列表）
        Target(screen: "savedThreads", waitElement: "我的收藏",       settle: 1.0),
        // 新增界面：黑名单（本地屏蔽列表）
        Target(screen: "blockedUsers", waitElement: "黑名单",         settle: 1.0),
    ]

    /// 已验收通过的界面（默认不跑）。需要全量回归时，把这组拼到 `targets` 后面即可。
    private let confirmedTargets = [
        Target(screen: "home",          waitElement: "home-post-open",    settle: 1.0),
        Target(screen: "threadReplies", waitElement: "detail-page-prev", settle: 2.5),
        Target(screen: "reply",         waitElement: "取消",              settle: 1.5),
        Target(screen: "userCard",      waitElement: "加好友",            settle: 1.5),
        Target(screen: "newPost",       waitElement: "发布",              settle: 1.0),
        Target(screen: "message",       waitElement: "消息",              settle: 1.2),
        Target(screen: "search",        waitElement: "home-post-open",    settle: 1.0),
        Target(screen: "boardManage",   waitElement: "添加",              settle: 1.0),
        Target(screen: "settings",      waitElement: "主题外观",           settle: 1.0),
        Target(screen: "security",      waitElement: "退出登录",           settle: 1.0),
        Target(screen: "login",         waitElement: "登录",              settle: 1.0),
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

            guard app.state == .runningForeground else {
                XCTFail("截图前 App 已不在前台: \(target.screen)")
                continue
            }

            // 等关键元素出现，确认界面真正渲染完成。
            waitForAnchor(app, target)

            let screenshot = app.screenshot()
            // Xcode 16 的 XCUIScreenshot.pngRepresentation 返回非可选 Data，直接取值。
            let pngData = screenshot.pngRepresentation
            // 强制 public.png，避免默认输出 HEIC 导致 xcresulttool export 后 find *.png 得到 0 张。
            let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
            attachment.name = "\(dark ? "dark" : "light")-\(target.screen)"
            attachment.lifetime = .keepAlways
            add(attachment)

            app.terminate()
        }
    }

    /// 等待关键元素出现（先按按钮查，再按静态文本查），最多等 12 秒。
    private func waitForAnchor(_ app: XCUIApplication, _ target: Target) {
        guard !target.waitElement.isEmpty else {
            Thread.sleep(forTimeInterval: target.settle)
            return
        }
        let text = target.waitElement
        if app.buttons[text].firstMatch.waitForExistence(timeout: 12) {
            Thread.sleep(forTimeInterval: target.settle)
            return
        }
        if app.staticTexts[text].firstMatch.waitForExistence(timeout: 3) {
            Thread.sleep(forTimeInterval: target.settle)
            return
        }
        print("[Screenshots] 警告: \(target.screen) 等待元素 \(text) 超时，仍按 settle 截图")
        Thread.sleep(forTimeInterval: target.settle)
    }
}
