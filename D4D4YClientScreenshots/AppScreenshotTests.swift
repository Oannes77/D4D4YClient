import XCTest

/// Codemagic 自动截图测试：演示模式下逐 Tab 截取 5 个目标界面（亮 / 暗各一套）。
///
/// 截图写入 `$TMPDIR/screenshots/{light|dark}/<tab>.png`，
/// 由 codemagic.yaml 的脚本拷到构建产物目录后作为 artifact 收集。
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

        let base = (ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory())
            .appendingPathComponent("screenshots")
            .appendingPathComponent(dark ? "dark" : "light")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        for name in screens {
            let button = app.tabBars.buttons[name]
            guard button.waitForExistence(timeout: 15) else {
                XCTFail("截图 Tab 不存在: \(name)")
                continue
            }
            button.tap()
            // 等布局稳定后再截。
            let _ = app.wait(for: .unknown, timeout: 1.5)
            if let data = app.screenshot().pngRepresentation {
                let url = base.appendingPathComponent("\(name).png")
                try? data.write(to: url)
            }
        }

        app.terminate()
    }
}
