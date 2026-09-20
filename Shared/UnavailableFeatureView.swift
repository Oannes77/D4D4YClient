import SwiftUI

/// 「尚未接入」占位页：用于**论坛需要登录态才能读取、而客户端还没接**的栏目。
///
/// 与项目「不伪造数据」原则一致：点进去**绝不给假列表**，
/// 而是说明为什么现在还没有内容，并给出一个**真实可用**的出口 ——
/// 在浏览器里打开论坛对应的网页版完成同一件事。
struct UnavailableFeatureView: View {
    let title: String
    let message: String
    /// 论坛网页版相对路径（相对 `HTTPClient.baseURL`）；nil 表示不提供网页入口。
    let webPath: String?

    @Environment(\.colorScheme) private var scheme

    private var webURL: URL? {
        guard let webPath else { return nil }
        return URL(string: webPath, relativeTo: HTTPClient.baseURL)?.absoluteURL
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "hourglass")
                .font(.largeTitle)
                .foregroundStyle(Color.appTextTertiary(scheme))

            Text(title)
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary(scheme))

            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.appTextSecondary(scheme))

            if let webURL {
                Link(destination: webURL) {
                    Text("在浏览器中打开论坛网页版")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.appPrimary(scheme))
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.top, 4)
                .accessibilityIdentifier("unavailable-web-link")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground(scheme))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}
