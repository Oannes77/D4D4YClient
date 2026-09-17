import SwiftUI

// MARK: - Hex 颜色初始化助手
/// 从 0xRRGGBB 构造 `Color`，避免在 View 中散落 RGB 分量。
extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

/// 与 `Color(hex:)` 对称的 `UIColor` 构造助手。
/// 用途：供 UIKit 层（如 `HTMLContentView` 的 `NSAttributedString` 主题着色）使用同一套 Hex 真值。
/// 真值集中在此扩展，不向各 View 散落 RGB 分量。
extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Theme Design Token
/// D4D4YClient 统一主题系统。
///
/// 设计方向：
/// - 浅色：薰衣草紫 / 粉紫渐变、白色文字（On Primary）、浅灰紫背景。
/// - 深色：深靛蓝紫、黑蓝背景、白色文字。
/// - 气质：安静、高级、克制，长时间阅读舒适。
///
/// 所有 View 均通过 `@Environment(\.colorScheme)` 或 `Color.app*(_:)` 取值，
/// 禁止在视图中硬编码颜色。
enum AppTheme {

    // MARK: 品牌主色
    /// 浅色模式主色：薰衣草紫。
    static let primaryLight = Color(hex: 0x9B8BD4)
    /// 深色模式主色：柔和的深紫。
    static let primaryDark  = Color(hex: 0xB69AE8)
    /// 浅模式主色 hover/按下：更深的紫。
    static let primaryLightPressed = Color(hex: 0x7D6DB8)
    /// 深模式主色 hover/按下。
    static let primaryDarkPressed = Color(hex: 0x967FD4)

    // MARK: 渐变
    /// 浅色品牌渐变：薰衣草紫 → 粉紫。
    static func brandGradientLight() -> LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x9B8BD4), Color(hex: 0xD8A6C8)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// 深色品牌渐变：深靛蓝 → 深紫。
    static func brandGradientDark() -> LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x4F46A5), Color(hex: 0x7C6BC4)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: 背景 / 表面
    /// 浅色背景：近乎白的浅灰紫。
    static let backgroundLight = Color(hex: 0xFAF9FC)
    /// 深色背景：黑蓝。
    static let backgroundDark  = Color(hex: 0x0B0F19)
    /// 浅色表面：纯白。
    static let surfaceLight    = Color(hex: 0xFFFFFF)
    /// 深色表面：深蓝灰。
    static let surfaceDark     = Color(hex: 0x12182B)
    /// 浅色二级表面：用于输入框、卡片式浮层。
    static let surfaceSecondaryLight = Color(hex: 0xF2F0F7)
    /// 深色二级表面。
    static let surfaceSecondaryDark  = Color(hex: 0x1A2235)

    // MARK: 文字
    /// 浅色主文字：深黑灰。
    static let textPrimaryLight   = Color(hex: 0x1C1C1E)
    /// 深色主文字：纯白。
    static let textPrimaryDark    = Color(hex: 0xFFFFFF)
    /// 浅色二级文字：中性灰。
    static let textSecondaryLight = Color(hex: 0x6B7280)
    /// 深色二级文字：冷灰蓝。
    static let textSecondaryDark  = Color(hex: 0xA0A8B8)
    /// 浅色三级文字：更淡的灰。
    static let textTertiaryLight  = Color(hex: 0x9CA3AF)
    /// 深色三级文字。
    static let textTertiaryDark   = Color(hex: 0x6B7280)

    // MARK: 分隔 / 边框
    static let dividerLight = Color(hex: 0xE8E5EE)
    static let dividerDark  = Color(hex: 0x2A3042)
    static let borderLight  = Color(hex: 0xDDD8E8)
    static let borderDark   = Color(hex: 0x3A4260)

    // MARK: 功能色
    static let successLight = Color(hex: 0x2E7D52)
    static let successDark  = Color(hex: 0x4ADE80)
    static let warningLight = Color(hex: 0xB45309)
    static let warningDark  = Color(hex: 0xFBBF24)
    static let errorLight   = Color(hex: 0xB91C1C)
    static let errorDark    = Color(hex: 0xF87171)
}

// MARK: - 动态取色便捷方法
extension Color {
    static func appPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? AppTheme.primaryDark : AppTheme.primaryLight
    }

    static func appPrimaryPressed(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? AppTheme.primaryDarkPressed : AppTheme.primaryLightPressed
    }

    static func appBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? AppTheme.backgroundDark : AppTheme.backgroundLight
    }

    static func appSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? AppTheme.surfaceDark : AppTheme.surfaceLight
    }

    static func appSurfaceSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? AppTheme.surfaceSecondaryDark : AppTheme.surfaceSecondaryLight
    }

    static func appTextPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight
    }

    static func appTextSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight
    }

    static func appTextTertiary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? AppTheme.textTertiaryDark : AppTheme.textTertiaryLight
    }

    static func appDivider(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? AppTheme.dividerDark : AppTheme.dividerLight
    }

    static func appBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? AppTheme.borderDark : AppTheme.borderLight
    }

    static func appSuccess(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? AppTheme.successDark : AppTheme.successLight
    }

    static func appWarning(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? AppTheme.warningDark : AppTheme.warningLight
    }

    static func appError(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? AppTheme.errorDark : AppTheme.errorLight
    }

    static func appBrandGradient(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark ? AppTheme.brandGradientDark() : AppTheme.brandGradientLight()
    }
}
