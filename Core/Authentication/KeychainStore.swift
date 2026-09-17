import Foundation
import Security

/// 认证凭据的安全存储（Keychain）。
///
/// 仅持久化服务端下发的鉴权 Cookie 值（`cdb_auth`）与会话快照（用户名 / uid），
/// **绝不**保存用户明文密码。SwiftData 不承载任何认证数据（与 Phase 2 设计决策一致）。
///
/// 非 actor 隔离：`SecItem` 为线程安全的 C API，可被 `@MainActor` 的 `SessionManager`
/// 与非隔离的 `LoginRepository` 同时安全调用。
final class KeychainStore {

    static let shared = KeychainStore()

    private let service = "com.d4d4y.client.auth"
    private let authTokenAccount = "cdb_auth"
    private let usernameAccount  = "session_username"
    private let uidAccount       = "session_uid"

    private init() {}

    // MARK: - 写入

    /// 保存一次成功登录的凭据。明文密码**不会**进入本方法。
    /// - Parameters:
    ///   - authToken: `cdb_auth` Cookie 值（鉴权令牌）。
    ///   - username: 会话用户名快照（展示用，真实值以服务器为准）。
    ///   - uid: 用户 UID（尽力而为，解析失败为 0）。
    func save(authToken: String, username: String, uid: Int) {
        write(authToken, account: authTokenAccount)
        write(username, account: usernameAccount)
        write(String(uid), account: uidAccount)
    }

    // MARK: - 读取

    /// 读取持久化的鉴权令牌；无则返回 nil。
    func loadAuthToken() -> String? {
        read(account: authTokenAccount)
    }

    /// 读取会话快照；任一字段缺失返回 nil。
    func loadSession() -> (username: String, uid: Int)? {
        guard let username = read(account: usernameAccount),
              let uidStr = read(account: uidAccount),
              let uid = Int(uidStr) else { return nil }
        return (username, uid)
    }

    // MARK: - 清除

    /// 退出登录时调用：删除全部认证相关条目（令牌 + 快照）。
    func clear() {
        for account in [authTokenAccount, usernameAccount, uidAccount] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    // MARK: - 底层

    private func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if SecItemCopyMatching(match as CFDictionary, nil) == errSecSuccess {
            let attrs: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(match as CFDictionary, attrs as CFDictionary)
        } else {
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
