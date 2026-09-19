import XCTest

/// Codemagic 自动截图测试：演示模式下逐屏截取 5 个目标界面（亮 / 暗各一套）。
///
/// 严格对照上午 HTML 原型（v3.0）的真实交互路径：
/// - TabBar 只有 **3 个**（首页 / 消息 / 我的），与正式发布一致；
/// - 「帖子详情」= 首页点第一个帖子进入（home-post-open）；
/// - 「回复框」= 帖子详情点回复按钮弹出底部 Sheet（detail-reply）。
///
/// 每屏独立 launch / terminate，避免导航状态互相污染；单个界面缺失不阻断其余截图。
/// 每张截图作为 `XCTAttachment`（`lifetime = .keepAlways`）随 .xcresult 结果包产出，
/// 由 codemagic.yaml 通过 `xcrun xcresulttool export` 导出为 png 作为 artifact 收集。
final class AppScreenshotTests: XCTestCase {

    private struct Target {
        let name: String
        /// 进入该界面后额外等待布局 / 数据稳定的秒数。
        let settle: TimeInterval
    }

    /// 顺序即导航顺序：首页 →（点帖子）帖子详情 →（点回复）回复框；消息 / 我的 直接切 Tab。
    private let targets = [
        Target(name: "首页", settle: 1.5),
        // 8s：覆盖首帖 HTMLContentView 同步渲染 + UITextView intrinsic size layout pass + 多次回顶。
        Target(name: "帖子详情", settle: 8.0),
        Target(name: "回复框", settle: 2.0),
        Target(name: "消息", settle: 1.5),
        Target(name: "我的", settle: 1.5),
        // 登录页：需 -DemoLogin 启动参数直接渲染（不进 Tab），单独验收登录模块视觉。
        Target(name: "登录", settle: 1.5),
    ]

    override func setUpWithError() throws {
        // 尽量多截几张：单个界面缺失不阻断其余截图。
        continueAfterFailure = true
    }

    func testLightScreenshots() { runScreenshots(dark: false) }
    func testDarkScreenshots() { runScreenshots(dark: true) }

    private func runScreenshots(dark: Bool) {
        for target in targets {
            let app = XCUIApplication()
            app.launchArguments = ["-DemoMode"]
            if dark { app.launchArguments.append("-DarkMode") }
            // 登录页不走 Tab 导航，靠该参数让 App 直接渲染登录门禁页。
            if target.name == "登录" { app.launchArguments.append("-DemoLogin") }

            if app.state == .runningForeground { app.terminate() }
            app.launch()

            navigate(to: target.name, app: app)

            guard app.state == .runningForeground else {
                XCTFail("截图前 App 已不在前台: \(target.name)")
                continue
            }

            let screenshot = app.screenshot()
            // Xcode 16 的 XCUIScreenshot.pngRepresentation 返回非可选 Data，直接取值。
            let pngData = screenshot.pngRepresentation
            // 强制 public.png，避免默认输出 HEIC 导致 xcresulttool export 后 find *.png 得到 0 张。
            let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
            attachment.name = "\(dark ? "dark" : "light")-\(target.name)"
            attachment.lifetime = .keepAlways
            add(attachment)

            app.terminate()
        }
    }

    private func navigate(to name: String, app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch

        switch name {
        case "首页":
            // Demo 启动默认落在首页，无需额外操作。
            break

        case "消息":
            let tab = tabBar.buttons.element(boundBy: 1)
            guard tab.waitForExistence(timeout: 10) else {
                XCTFail("消息 Tab 不存在")
                return
            }
            tab.tap()

        case "我的":
            let tab = tabBar.buttons.element(boundBy: 2)
            guard tab.waitForExistence(timeout: 10) else {
                XCTFail("我的 Tab 不存在")
                return
            }
            tab.tap()

        case "登录":
            // -DemoLogin 启动即渲染登录页，无需额外导航。
            break

        case "帖子详情":
            let homeTab = tabBar.buttons.element(boundBy: 0)
            if homeTab.waitForExistence(timeout: 10) { homeTab.tap() }
            let post = app.buttons["home-post-open"].firstMatch
            guard post.waitForExistence(timeout: 10) else {
                XCTFail("首页帖子不可点（home-post-open 缺失）")
                return
            }
            post.tap()
            // 等详情 push 动画 + HTMLContentView 同步渲染 + UITextView 尺寸稳定 + 首帖回顶。
            _ = app.wait(for: .unknown, timeout: 8.0)

        case "回复框":
            let homeTab = tabBar.buttons.element(boundBy: 0)
            if homeTab.waitForExistence(timeout: 10) { homeTab.tap() }
            let post = app.buttons["home-post-open"].firstMatch
            guard post.waitForExistence(timeout: 10) else {
                XCTFail("首页帖子不可点（home-post-open 缺失）")
                return
            }
            post.tap()
            _ = app.wait(for: .unknown, timeout: 8.0)
            let reply = app.buttons["detail-reply"].firstMatch
            guard reply.waitForExistence(timeout: 10) else {
                XCTFail("回复按钮不可点（detail-reply 缺失）")
                return
            }
            reply.tap()
            // 等回复 Sheet 弹出并稳定。
            _ = app.wait(for: .unknown, timeout: 2.0)

        default:
            break
        }
    }
}
