import SwiftUI

/// 账号与安全。
///
/// 展示当前账号快照，并提供退出登录。**不展示、不存储任何明文密码。**
/// 修改密码 / 修改签名需图形验证码，当前版本不内置，明确引导用户到网页端完成。
struct AccountSecurityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: SessionManager

    @State private var showLogoutConfirm = false

    private var username: String {
        session.state.session?.username ?? "已登录用户"
    }

    private var uid: Int {
        session.state.session?.uid ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    accountCard
                    hintCard
                    logoutButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.appBackground(scheme))
            .scrollContentBackground(.hidden)
            .navigationTitle("账号与安全")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("退出登录", isPresented: $showLogoutConfirm) {
                Button("退出", role: .destructive) {
                    session.logout()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除本机保存的登录凭据，需要重新登录才能浏览会员内容。")
            }
        }
        .tint(Color.appPrimary(scheme))
    }

    private var accountCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.appPrimary(scheme))

            VStack(alignment: .leading, spacing: 4) {
                Text(username)
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary(scheme))
                Text(uid > 0 ? "UID \(uid)" : "UID 未知")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary(scheme))
            }

            Spacer()
        }
        .padding(16)
        .appCard(scheme)
    }

    private var hintCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关于凭据")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.appTextPrimary(scheme))
            Text("登录凭据保存在系统钥匙串（Keychain），不会写入本地数据库，也不会保存明文密码。修改密码、修改签名需要论坛图形验证码，请在网页端完成。")
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .appCard(scheme)
    }

    private var logoutButton: some View {
        Button {
            showLogoutConfirm = true
        } label: {
            Text("退出登录")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .background(Color.appSurface(scheme))
        .foregroundStyle(Color.appError(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appDivider(scheme), lineWidth: 0.5)
        )
    }
}
