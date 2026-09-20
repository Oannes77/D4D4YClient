import Foundation
import Combine

/// 客户端偏好（`UserDefaults` 支撑的单例，SwiftUI 可直接绑定）。
///
/// **为什么不用 SwiftData**：这几项是纯客户端开关，需要
/// 1) 在 App 启动极早期（注册后台刷新）读到；
/// 2) 在后台任务里读到（那时还没有 SwiftUI 上下文）；
/// 3) 避免给已有安装做数据迁移。
/// 它们全部只改变**本机行为**，不修改论坛上的任何数据。
final class PreferenceStore: ObservableObject {

    static let shared = PreferenceStore()

    /// 占位符默认值（论坛最短字数规则用的凑字文本）。
    static let defaultReplyPlaceholder = "Peace&Love"

    private let defaults: UserDefaults

    private enum Key {
        static let replyPlaceholder = "pref.replyPlaceholder"
        static let showPostContent  = "pref.showPostContent"
        static let pushMinutes      = "pref.pushMinutes"
        static let lastPushCheckAt  = "pref.lastPushCheckAt"
    }

    /// 回帖 / 发帖时**自动附加**的占位符：与正文隔一空行，不显示在输入框内。
    /// 用户可在「我的 → 回帖占位符」里改（默认 `Peace&Love`）。
    @Published var replyPlaceholder: String {
        didSet { defaults.set(replyPlaceholder, forKey: Key.replyPlaceholder) }
    }

    /// 首页 / 搜索结果列表是否显示帖子正文预览。
    /// 关闭后列表只显示标题 + 作者 + 图片，更省屏幕（网络请求与解析不受影响）。
    @Published var showPostContent: Bool {
        didSet { defaults.set(showPostContent, forKey: Key.showPostContent) }
    }

    /// 后台刷新间隔（分钟）；`0` = 关闭。
    /// 写入后立即重新排期（见 `BackgroundRefresh.scheduleNext()`）。
    @Published var pushFrequencyMinutes: Int {
        didSet {
            defaults.set(pushFrequencyMinutes, forKey: Key.pushMinutes)
            BackgroundRefresh.scheduleNext()
        }
    }

    /// 最近一次后台刷新成功的时间（用于设置页如实显示；从未刷新过为 nil）。
    @Published var lastPushCheckAt: Date? {
        didSet { defaults.set(lastPushCheckAt, forKey: Key.lastPushCheckAt) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 注意：初始化期间不会触发 didSet，故不会写回 UserDefaults。
        self.replyPlaceholder = defaults.string(forKey: Key.replyPlaceholder)
            ?? Self.defaultReplyPlaceholder
        self.showPostContent = defaults.object(forKey: Key.showPostContent) as? Bool ?? true
        self.pushFrequencyMinutes = defaults.integer(forKey: Key.pushMinutes)
        self.lastPushCheckAt = defaults.object(forKey: Key.lastPushCheckAt) as? Date
    }

    // MARK: - 展示用文案

    /// 占位符整理：去掉首尾空白；空串回落默认值（避免发出「只有空行」的回复）。
    static func sanitizedPlaceholder(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultReplyPlaceholder : trimmed
    }

    /// 可选的后台刷新间隔。
    /// 用一个小结构体而不是元组数组：`ForEach` 的 `id:` 需要 KeyPath，
    /// 而 Swift 的 KeyPath **不能指向元组元素**（`\.minutes` 会编译报错）。
    struct PushOption: Identifiable, Hashable {
        let minutes: Int
        let label: String
        var id: Int { minutes }
    }

    /// 可选的后台刷新间隔（0 = 关闭）。
    static let pushOptions: [PushOption] = [
        PushOption(minutes: 0,  label: "关闭"),
        PushOption(minutes: 15, label: "15 分钟"),
        PushOption(minutes: 30, label: "30 分钟"),
        PushOption(minutes: 60, label: "60 分钟")
    ]

    /// 当前设置的中文文案（设置框右侧显示）。
    var pushLabel: String {
        Self.pushOptions.first { $0.minutes == pushFrequencyMinutes }?.label
            ?? "\(pushFrequencyMinutes) 分钟"
    }
}
