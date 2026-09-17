import XCTest

/// Codemagic 自动截图测试：演示模式下逐 Tab 截取 5 个目标界面（亮 / 暗各一套）。
///
/// 每张截图作为 `XCTAttachment`（`lifetime = .keepAlways`）随 .xcresult 结果包产出，
/// 由 codemagic.yaml 通过 `xcrun xcresulttool export` 导出为 png 作为 artifact 收集。
/// 不依赖任何模拟器沙盒临时目录（避免 host 与模拟器 $TMPDIR 不一致导致收集不到）。
final class AppScreenshotTests: XCTestCase {

    private let screens = ["首页", "板块", "帖子详情", "回复框", "图片预览"]

    override func setUpWithError() throws {
        // 尽量多截几张：单个 Tab 缺失不阻断其余截图。
        continueAfterFailure = true
    }

    func testLightScreenshots() {
        runScreenshots(dark: false)
    }

    func testDarkScreenshots() {
        runScreenshots(dark: true)
    }

    private func runScreenshots(dark: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoMode"]
        if dark { app.launchArguments.append("-DarkMode") }
        app.launch()

        for name in screens {
            let button = app.tabBars.buttons[name]
            guard button.waitForExistence(timeout: 15) else {
                XCTFail("截图 Tab 不存在: \(name)")
                continue
            }
            button.tap()
            // 等布局稳定后再截。
            let _ = app.wait(for: .unknown, timeout: 1.5)
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(image: screenshot.image)
            attachment.name = "\(dark ? "dark" : "light")-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        app.terminate()
    }
}
