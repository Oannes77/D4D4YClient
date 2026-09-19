import SwiftUI
import UIKit

/// 向上遍历 superview 链，捕获当前视图所在的 `UIScrollView`，供外部直接控制 `contentOffset`。
///
/// 用途：帖子详情首帖回顶。SwiftUI `ScrollViewReader.scrollTo` 在内容高度异步增长
/// （HTMLContentView 渲染 NSAttributedString）的场景下不可靠——目标 id 的 y 坐标持续下移，
/// scrollTo 的 request 总被新增长的高度抵消，最终停在长帖中部。
/// 改用 UIKit 直接 `setContentOffset(.zero, animated: false)` 强制置顶，结果确定。
final class ScrollHolder: ObservableObject {
    weak var scrollView: UIScrollView?
}

private final class ScrollCaptureUIView: UIView {
    var onCapture: ((UIScrollView) -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        var node: UIView? = self
        while let current = node {
            if let scrollView = current as? UIScrollView {
                onCapture?(scrollView)
                break
            }
            node = current.superview
        }
    }
}

struct ScrollCaptureRepresentable: UIViewRepresentable {
    var onCapture: (UIScrollView) -> Void
    func makeUIView(context: Context) -> UIView {
        let view = ScrollCaptureUIView()
        view.onCapture = onCapture
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
