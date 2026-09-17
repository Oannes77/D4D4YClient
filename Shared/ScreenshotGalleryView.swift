import SwiftUI
import SwiftData

/// 仅 `-DemoMode` 下作为应用根视图：用真实组件 + 离线样例数据，
/// 以 TabView 逐屏呈现 5 个目标界面，供 Codemagic 截图验证设计令牌。
///
/// 不改动任何正常发布路径；仅当启动参数含 `-DemoMode` 时由 `D4D4YApp` 选用。
struct ScreenshotGalleryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house") }

            ForumListView()
                .tabItem { Label("板块", systemImage: "square.stack.3d.up") }

            ThreadDetailView(thread: DemoData.sampleThread)
                .tabItem { Label("帖子详情", systemImage: "doc.text") }

            NavigationStack {
                ReplyEditor(viewModel: ReplyViewModel(tid: 1)) { }
                    .navigationTitle("回复")
            }
            .tabItem { Label("回复框", systemImage: "square.and.pencil") }

            Group {
                if let url = DemoData.sampleImageURL {
                    ImageViewer(url: url)
                } else {
                    Color.black.ignoresSafeArea()
                }
            }
            .tabItem { Label("图片预览", systemImage: "photo") }
        }
        .tint(Color.appPrimary(scheme))
        .preferredColorScheme(DemoMode.isDark ? .dark : nil)
        .environmentObject(SessionManager.shared)
        .task {
            DemoData.seed(context: context)
            SessionManager.shared.enterDemoSession()
        }
    }
}
