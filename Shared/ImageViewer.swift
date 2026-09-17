import SwiftUI

/// 可被 `fullScreenCover(item:)` 承载的图片载体。
struct FullScreenImage: Identifiable {
    let id = UUID()
    let url: URL
}

/// 全屏图片查看器。
///
/// 设计约束（Sprint 4）：
/// - 全屏 + 暗色背景，专注看图。
/// - 支持捏合缩放（`MagnificationGesture`，1.0–4.0 倍）与拖拽平移（仅缩放后可平移）。
/// - 双击复位缩放/位置；右上角关闭按钮退出。
/// - 图片加载失败给出明确提示，不静默白屏。
struct ImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding()
        }
        .statusBarHidden(true)
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
