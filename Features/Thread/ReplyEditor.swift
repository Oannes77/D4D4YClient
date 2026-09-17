import SwiftUI

/// 帖子详情页底部回复编辑器。
///
/// - 登录用户：输入框 + 紫色发送按钮。
/// - 游客：登录提示按钮，点击后弹出登录页。
/// - 不直接触碰 Cookie / formhash / POST / GBK；一切交给 `ReplyViewModel` → `ReplyRepository`。
struct ReplyEditor: View {
    @ObservedObject var viewModel: ReplyViewModel
    @EnvironmentObject private var session: SessionManager
    @Environment(\.colorScheme) private var scheme
    @State private var showLoginSheet = false

    /// 提交成功后触发，通常由父视图刷新帖子内容。
    let onSuccess: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.appDivider(scheme))

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.appError(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.appSurface(scheme))
            }

            if let success = viewModel.successMessage {
                Text(success)
                    .font(.caption)
                    .foregroundStyle(Color.appSuccess(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.appSurface(scheme))
            }

            HStack(alignment: .center, spacing: 12) {
                switch session.state {
                case .authenticated:
                    editorContent
                case .guest, .failed, .authenticating:
                    guestPrompt
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.appSurface(scheme))
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
        }
    }

    // MARK: - 登录用户编辑区

    private var editorContent: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextEditor(text: $viewModel.message)
                .font(.body)
                .lineLimit(1...5)
                .scrollContentBackground(.hidden)
                .background(Color.appSurfaceSecondary(scheme))
                .cornerRadius(8)
                .frame(minHeight: 40, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.appBorder(scheme), lineWidth: 0.5)
                )
                .onChange(of: viewModel.message) { _ in
                    viewModel.clearFeedback()
                }

            submitButton
        }
    }

    private var submitButton: some View {
        Button {
            Task {
                await viewModel.submit(onSuccess: onSuccess)
            }
        } label: {
            if viewModel.isSubmitting {
                ProgressView()
                    .tint(.white)
                    .frame(width: 44, height: 36)
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 36)
            }
        }
        .background(
            viewModel.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Color.appPrimary(scheme).opacity(0.4)
                : Color.appPrimary(scheme)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .disabled(viewModel.isSubmitting || viewModel.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - 游客提示

    private var guestPrompt: some View {
        Button {
            showLoginSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .foregroundStyle(Color.appPrimary(scheme))
                Text("登录后参与回复")
                    .foregroundStyle(Color.appTextPrimary(scheme))
                Spacer()
                Text("去登录")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appPrimary(scheme))
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}
