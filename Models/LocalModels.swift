import Foundation
import SwiftData

// MARK: - 本地持久化模型（SwiftData）
// 与网络值模型（ForumThread / Post / ForumSection 等 struct）严格分离：
// 这里只保存用户本地状态，不缓存任何服务器内容。

/// 固定板块（首页常用板块）。
@Model
final class PinnedForum {
    @Attribute(.unique) var fid: Int
    var name: String
    var sortOrder: Int

    init(fid: Int, name: String, sortOrder: Int) {
        self.fid = fid
        self.name = name
        self.sortOrder = sortOrder
    }

    // MARK: - 固定 / 取消固定（本地操作，不修改服务器数据）

    /// 固定一个板块：已存在则仅更新名称，否则按当前最大 sortOrder + 1 追加。
    @MainActor
    static func pin(fid: Int, name: String, context: ModelContext) {
        let descriptor = FetchDescriptor<PinnedForum>(
            predicate: #Predicate { $0.fid == fid }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.name = name
        } else {
            let nextOrder = (try? context.fetch(FetchDescriptor<PinnedForum>()))
                .map { $0.map(\.sortOrder).max() ?? 0 } ?? 0
            context.insert(PinnedForum(fid: fid, name: name, sortOrder: nextOrder + 1))
        }
        try? context.save()
    }

    /// 取消固定（按 fid 删除）。
    @MainActor
    static func unpin(fid: Int, context: ModelContext) {
        let descriptor = FetchDescriptor<PinnedForum>(
            predicate: #Predicate { $0.fid == fid }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            context.delete(existing)
            try? context.save()
        }
    }

    /// 是否已固定。
    @MainActor
    static func isPinned(fid: Int, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<PinnedForum>(
            predicate: #Predicate { $0.fid == fid }
        )
        return (try? context.fetch(descriptor))?.first != nil
    }
}

/// 被本地屏蔽的作者（仅影响本地阅读过滤，不修改服务器数据）。
@Model
final class BlockedUser {
    @Attribute(.unique) var uid: Int
    var username: String
    var createdAt: Date

    init(uid: Int, username: String, createdAt: Date = .now) {
        self.uid = uid
        self.username = username
        self.createdAt = createdAt
    }

    // MARK: - 屏蔽 / 取消屏蔽（本地操作，不修改服务器数据）

    /// 屏蔽一个作者：已屏蔽则幂等忽略。
    @MainActor
    static func block(uid: Int, username: String, context: ModelContext) {
        let descriptor = FetchDescriptor<BlockedUser>(
            predicate: #Predicate { $0.uid == uid }
        )
        if (try? context.fetch(descriptor))?.first == nil {
            context.insert(BlockedUser(uid: uid, username: username))
            try? context.save()
        }
    }

    /// 取消屏蔽（按 uid 删除）。
    @MainActor
    static func unblock(uid: Int, context: ModelContext) {
        let descriptor = FetchDescriptor<BlockedUser>(
            predicate: #Predicate { $0.uid == uid }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            context.delete(existing)
            try? context.save()
        }
    }

    /// 是否已屏蔽该作者。
    @MainActor
    static func isBlocked(uid: Int, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<BlockedUser>(
            predicate: #Predicate { $0.uid == uid }
        )
        return (try? context.fetch(descriptor))?.first != nil
    }
}

/// 浏览历史（只存 tid + 标题快照 + 时间，便于历史列表不回查网络）。
@Model
final class ReadHistory {
    @Attribute(.unique) var tid: Int
    /// 标题快照：仅用于历史列表展示，**不作为唯一真实来源**；
    /// 真实标题 / 正文一律以网络解析结果为准，快照仅作离线占位。
    var title: String
    /// 预留：所属版块 ID，便于后续按板块归类历史（当前不强制依赖）。
    var forumID: Int?
    var lastReadTime: Date
    /// 最近一次阅读到的楼层 pid（用于未来「继续阅读」；nil 表示尚未记录具体楼层）。
    var lastReadPostID: Int?

    // MARK: - Future 优化记录
    // 未来优化①：增加 `var scrollOffset: Double?` 记录帖子详情滚动位置，
    // 支撑「继续阅读」精确滚动定位（当前仅以末楼 pid 为锚点，未追踪真实滚动位置）。

    init(tid: Int, title: String, forumID: Int? = nil, lastReadTime: Date = .now, lastReadPostID: Int? = nil) {
        self.tid = tid
        self.title = title
        self.forumID = forumID
        self.lastReadTime = lastReadTime
        self.lastReadPostID = lastReadPostID
    }

    // MARK: - 记录阅读（本地操作，不修改服务器数据）

    /// 记录一次阅读：已存在则刷新标题 / 版块 / 时间，可选写入最近楼层；否则新建（按 tid 唯一）。
    /// 在主线程调用（SwiftUI onAppear / task / onDisappear 上下文）。
    @MainActor
    static func record(tid: Int, title: String, forumID: Int? = nil, lastReadPostID: Int? = nil, context: ModelContext) {
        let descriptor = FetchDescriptor<ReadHistory>(
            predicate: #Predicate { $0.tid == tid }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.title = title
            existing.forumID = forumID
            existing.lastReadTime = .now
            if let pid = lastReadPostID { existing.lastReadPostID = pid }
        } else {
            let history = ReadHistory(tid: tid, title: title, forumID: forumID, lastReadPostID: lastReadPostID)
            context.insert(history)
        }
        try? context.save()
    }
}

/// 最近访问板块（首页「最近访问板块」区数据源）。
/// 仅记录本地访问行为，不触发额外网络请求。
@Model
final class VisitedForum {
    @Attribute(.unique) var fid: Int
    var name: String
    var lastVisitedAt: Date

    init(fid: Int, name: String, lastVisitedAt: Date = .now) {
        self.fid = fid
        self.name = name
        self.lastVisitedAt = lastVisitedAt
    }

    /// 记录一次板块访问：已存在则刷新时间（并更新名称），否则新建。
    /// 在主线程调用（SwiftUI onAppear / task 上下文）。
    @MainActor
    static func record(fid: Int, name: String, context: ModelContext) {
        let descriptor = FetchDescriptor<VisitedForum>(
            predicate: #Predicate { $0.fid == fid }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.lastVisitedAt = .now
            existing.name = name
        } else {
            context.insert(VisitedForum(fid: fid, name: name))
        }
        try? context.save()
    }
}

/// 本地阅读设置（单例：slot = "singleton"）。
@Model
final class LocalSettings {
    @Attribute(.unique) var slot: String
    /// "system" | "light" | "dark"
    var themeMode: String
    var fontSize: Double
    var lineSpacing: Double
    /// "compact" | "normal" | "comfortable"
    var listDensity: String

    init(slot: String = "singleton",
         themeMode: String = "system",
         fontSize: Double = 17,
         lineSpacing: Double = 1.5,
         listDensity: String = "normal") {
        self.slot = slot
        self.themeMode = themeMode
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.listDensity = listDensity
    }
}

/// 主题媒体元数据缓存（方案 B：延迟检测 + 缓存）。
///
/// 与网络模型 ForumThread 完全分离：列表只显示轻量 📷 / 📎 标识，
/// 真实媒体信息由 ImageMetadataRepository 检测后写入此处，24 小时内有效。
/// 不修改任何服务器数据，仅本地加速「该帖是否含图 / 含附件」的判断。
/// 不做图片数量 / 缩略图 / 图墙，保持简单（Sprint 9B 重定义）。
@Model
final class ThreadMediaCache {
    @Attribute(.unique) var tid: Int
    var hasImage: Bool
    /// 第一张有效正文图片（绝对 URL 字符串），无图时为 nil。
    var previewImageURL: String?
    var hasAttachment: Bool
    var detectedAt: Date

    init(tid: Int, hasImage: Bool, previewImageURL: String?,
         hasAttachment: Bool, detectedAt: Date = .now) {
        self.tid = tid
        self.hasImage = hasImage
        self.previewImageURL = previewImageURL
        self.hasAttachment = hasAttachment
        self.detectedAt = detectedAt
    }

    /// 缓存是否有效（24 小时）。过期后由 ImageMetadataRepository 重新检测。
    var isFresh: Bool {
        Date().timeIntervalSince(detectedAt) < 24 * 3600
    }

    /// 预览图（点击 📷 打开 ImageViewer）。
    var previewURL: URL? {
        previewImageURL.flatMap { URL(string: $0) }
    }

    // MARK: - 本地缓存写入 / 读取（主线程，SwiftUI 上下文）

    /// 写入或更新一条缓存（按 tid 唯一）。在主线程调用。
    @MainActor
    static func upsert(_ info: ThreadMediaInfo, context: ModelContext) {
        let descriptor = FetchDescriptor<ThreadMediaCache>(
            predicate: #Predicate { $0.tid == info.tid }
        )
        let url = info.previewImageURL?.absoluteString
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.hasImage = info.hasImage
            existing.previewImageURL = url
            existing.hasAttachment = info.hasAttachment
            existing.detectedAt = .now
        } else {
            context.insert(ThreadMediaCache(
                tid: info.tid,
                hasImage: info.hasImage,
                previewImageURL: url,
                hasAttachment: info.hasAttachment
            ))
        }
        try? context.save()
    }

    /// 读取某 tid 的缓存（可能为 nil：尚未检测 / 已过期且未刷新）。
    @MainActor
    static func cache(for tid: Int, context: ModelContext) -> ThreadMediaCache? {
        let descriptor = FetchDescriptor<ThreadMediaCache>(
            predicate: #Predicate { $0.tid == tid }
        )
        return (try? context.fetch(descriptor))?.first
    }
}
