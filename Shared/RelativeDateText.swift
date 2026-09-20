import Foundation

/// 本地时间的**中文友好**文案（用于客户端自己产生的时间：收藏时间、上次刷新时间等）。
///
/// 论坛页面上给出的时间原文（如「2004-11-3 22:22」「昨天 21:04」）一律原样展示，
/// 不走这里 —— 那些是服务器口径，不做二次翻译，避免出现两边不一致。
enum RelativeDateText {

    /// 今天 09:02 / 昨天 21:04 / 9月18日 / 2025年9月18日
    static func friendly(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "今天 \(time(date))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(time(date))"
        }
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return "\(month)月\(day)日"
        }
        return "\(calendar.component(.year, from: date))年\(month)月\(day)日"
    }

    /// 只要日期部分：今天 / 昨天 / 9月18日 / 2025年9月18日。
    static func friendlyDay(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let full = friendly(date, now: now, calendar: calendar)
        // 去掉「今天 / 昨天」后面的具体时刻。
        if let space = full.firstIndex(of: " ") {
            return String(full[full.startIndex..<space])
        }
        return full
    }

    private static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// 只关心「时:分」，固定 zh_CN 与 24 小时制（跟随系统区域会出现 12 小时制，与论坛口径不一致）。
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
