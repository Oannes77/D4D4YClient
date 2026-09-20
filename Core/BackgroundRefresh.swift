import Foundation
import BackgroundTasks

/// 后台刷新（消息未读提醒）。
///
/// 做什么：iOS 在后台按用户设定的间隔唤起本 App，拉一次 `pm.php` 收件箱，
/// 把**真实未读数**写入消息 Tab 的角标（与前台同一口径：读不到就是 0，不写死数字）。
///
/// **诚实说明（同样写在设置页里）**：
/// - 实际唤起时机由 iOS 决定（受电量、使用习惯、低电量模式影响），只能保证「按间隔尝试」，不保证准时；
/// - 收件箱需要登录态，未登录时后台刷新只会返回「需要登录」，不会伪造任何未读数字。
///
/// 稳定性设计：`BGTaskScheduler.register` 要求标识已写入 Info.plist 的
/// `BGTaskSchedulerPermittedIdentifiers`，否则会抛 ObjC 异常（直接崩溃）。
/// 因此这里**先检查构建配置**再注册，缺配置时安静降级为「不刷新」，绝不崩溃。
enum BackgroundRefresh {

    /// 后台任务标识（必须与 Info.plist 的 BGTaskSchedulerPermittedIdentifiers 一致）。
    static let taskIdentifier = "com.d4d4y.client.refresh"

    private static var hasRegistered = false

    /// 构建是否带上了后台任务标识。
    static var isConfigured: Bool {
        let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        return ids?.contains(taskIdentifier) == true
    }

    // MARK: - 注册（App 启动时调用一次）

    /// 注册后台任务处理器。
    ///
    /// 注意：**无论用户当前是否开启推送都要注册**——任务处理器必须与标识一起在启动时登记，
    /// 否则之后 `submit` 一个未注册的任务会抛异常。是否真的排期由 `scheduleNext()` 决定。
    static func register() {
        guard !hasRegistered else { return }
        guard isConfigured else {
            Log.network.notice("后台刷新未启用：Info.plist 缺少 BGTaskSchedulerPermittedIdentifiers")
            return
        }
        hasRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            handle(task)
        }
    }

    // MARK: - 排期

    /// 按当前设置排下一次刷新；设置为「关闭」时取消已排期的请求。
    /// 可安全地在任何时候调用（未注册时 submit 会抛异常，故这里先判断）。
    static func scheduleNext() {
        guard isConfigured, hasRegistered else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)

        let minutes = PreferenceStore.shared.pushFrequencyMinutes
        guard minutes > 0 else { return }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(minutes * 60))
        do {
            try BGTaskScheduler.shared.submit(request)
            Log.network.notice("已排期后台刷新：\(minutes, privacy: .public) 分钟后")
        } catch {
            Log.network.error("后台刷新排期失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 执行

    private static func handle(_ task: BGTask) {
        // 先把下一次排上，保证刷新链条不会因为一次回调而断掉。
        scheduleNext()
        let refresh = Task { await refreshUnread() }
        task.expirationHandler = { refresh.cancel() }
        Task {
            let ok = await refresh.value
            task.setTaskCompleted(success: ok)
        }
    }

    /// 拉一次收件箱并更新未读角标。返回是否成功读到（登录门 / 网络失败都算失败，且不改动角标以外的任何状态）。
    @discardableResult
    static func refreshUnread() async -> Bool {
        let result = await PMRepository().inbox()
        switch result {
        case .success(let messages):
            // 页面没给出未读标记的条目不算未读（isUnread == nil → 不计入），不猜测。
            let unread = messages.filter { $0.isUnread == true }.count
            await MainActor.run {
                UnreadBadge.shared.setPrivateMessages(unread)
                PreferenceStore.shared.lastPushCheckAt = .now
            }
            Log.network.notice("后台刷新完成，未读 \(unread, privacy: .public) 条")
            return true
        case .failure(let error):
            Log.network.notice("后台刷新未取到数据: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
