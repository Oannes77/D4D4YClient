import SwiftUI

/// 统一的错误展示行。Debug 构建下附带解析/网络诊断详情。
/// 从原 HomeView 中提取到 Shared，供各列表/详情页共用。
struct ErrorRow: View {
    let message: String
    let debugDetail: String
    let retry: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).foregroundStyle(Color.appError(scheme))
            #if DEBUG
            Text(debugDetail)
                .font(.caption2)
                .foregroundStyle(Color.appTextTertiary(scheme))
            #endif
            Button("重试", action: retry)
                .buttonStyle(.bordered)
        }
    }
}
