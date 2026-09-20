import SwiftUI

/// 可被 `fullScreenCover(item:)` 承载的**单图**载体（列表封面图 / 📷 预览）。
struct FullScreenImage: Identifiable {
    let id = UUID()
    let url: URL
}

/// 可被 `fullScreenCover(item:)` 承载的**多图**载体（楼层正文内嵌图片）。
///
/// 点任意一张缩略图进入全屏后，可左右滑动浏览**同一楼层**的全部图片，并显示「第 n / N 张」。
struct FullScreenGallery: Identifiable {
    let id = UUID()
    let urls: [URL]
    let startIndex: Int
}

/// 全屏图片查看器。
///
/// 设计约束：
/// - 全屏 + 暗色背景，专注看图。
/// - 单图与多图统一入口：多图用 `TabView(.page)` 左右翻页，顶部显示「n / N」。
/// - 每张图独立支持捏合缩放（1.0–4.0 倍）与缩放后拖拽平移、双击复位。
/// - 图片加载失败给出明确提示，不静默白屏。
struct ImageViewer: View {
    let urls: [URL]
    @State private var index: Int

    @Environment(\.dismiss) private var dismiss

    /// 单图入口（保持既有调用方不变）。
    init(url: URL) {
        self.urls = [url]
        _index = State(initialValue: 0)
    }

    /// 多图入口：从第 `startIndex` 张开始看。
    init(urls: [URL], startIndex: Int = 0) {
        self.urls = urls
        let clamped = urls.isEmpty ? 0 : max(0, min(startIndex, urls.count - 1))
        _index = State(initialValue: clamped)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if urls.isEmpty {
                Text("没有可查看的图片")
                    .font(.footnote)
                    .foregroundStyle(.white)
            } else if urls.count == 1 {
                ZoomableImage(url: urls[0])
            } else {
                TabView(selection: $index) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { pair in
                        ZoomableImage(url: pair.element)
                            .tag(pair.offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .overlay(alignment: .top) {
            if urls.count > 1 { pageIndicator }
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .statusBarHidden(true)
    }

    // MARK: - 浮层

    /// 页码指示：第 n / N 张（多图时才出现）。
    private var pageIndicator: some View {
        Text("\(index + 1) / \(urls.count)")
            .font(.footnote).fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())
            .padding(.top, 12)
            .accessibilityIdentifier("image-viewer-index")
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding()
    }
}

/// 单张可缩放图片：自己的缩放 / 平移状态，翻页时互不影响。
private struct ZoomableImage: View {
    let url: URL

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView().tint(.white)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnification)
                    // 与 TabView 的翻页手势并存：未放大时拖拽等于翻页，放大后才平移。
                    .simultaneousGesture(drag)
                    .onTapGesture(count: 2) { reset() }
            case .failure:
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                    Text("图片加载失败")
                        .font(.footnote)
                        .foregroundStyle(.white)
                }
            @unknown default:
                EmptyView()
            }
        }
    }

    // MARK: - 手势

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                scale = min(max(scale * delta, 1.0), 4.0)
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale < 1.0 {
                    withAnimation { scale = 1.0 }
                }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.0 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func reset() {
        withAnimation {
            scale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
}
