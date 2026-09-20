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
extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Theme Design Token
/// D4D4YClient 统一主题系统（Threads 风格）。
///
/// 设计方向（2026-09-18 锁定）：
/// - 强调色：紫色 `#534AB7`（浅色主紫）。
/// - 深色：纯黑底 `#000`，紫提亮 `#8F86E8`。
/// - 扁平、克制、长读舒适，0.5px 细分割线、无阴影。
///
/// 所有 View 均通过 `Color.app*(_:)` 取值，禁止硬编码颜色。
enum AppTheme {

    // MARK: 品牌主色（Threads 紫）
    /// 浅色主色：紫 `#534AB7`。
    static let primaryLight = Color(hex: 0x534AB7)
    /// 深色主色：提亮紫 `#8F86E8`。
    static let primaryDark  = Color(hex: 0x8F86E8)
    /// 浅模式按下：更深的紫。
    static let primaryLightPressed = Color(hex: 0x423A91)
    /// 深模式按下。
    static let primaryDarkPressed = Color(hex: 0x7A6FD0)

    // MARK: 背景 / 表面
    /// 浅色背景：近白。
    static let backgroundLight = Color(hex: 0xFFFFFF)
    /// 深色背景：纯黑 `#000`（规避黑屏，文字走 --text 变量）。
    static let backgroundDark  = Color(hex: 0x000000)
    /// 浅色表面：纯白。
    static let surfaceLight    = Color(hex: 0xFFFFFF)
    /// 深色表面：近黑灰（比纯黑背景稍亮，使卡片/输入区可见）。
    static let surfaceDark     = Color(hex: 0x161616)
    /// 浅色二级表面：用于输入框、卡片式浮层。
    static let surfaceSecondaryLight = Color(hex: 0xF2F0F7)
    /// 深色二级表面。
    static let surfaceSecondaryDark  = Color(hex: 0x1F1F1F)

    // MARK: 文字
    static let textPrimaryLight   = Color(hex: 0x1C1C1E)
    static let textPrimaryDark    = Color(hex: 0xFFFFFF)
    static let textSecondaryLight = Color(hex: 0x6B7280)
    static let textSecondaryDark  = Color(hex: 0xA0A0A0)
    static let textTertiaryLight  = Color(hex: 0x9CA3AF)
    static let textTertiaryDark   = Color(hex: 0x6B6B6B)

    // MARK: 分隔 / 边框
    static let dividerLight = Color(hex: 0xE8E5EE)
    static let dividerDark  = Color(hex: 0x2A2A2A)
    static let borderLight  = Color(hex: 0xDDD8E8)
    static let borderDark   = Color(hex: 0x333333)

    // MARK: 功能色
    static let successLight = Color(hex: 0x2E7D52)
    static let successDark  = Color(hex: 0x4ADE80)
    static let warningLight = Color(hex: 0xB45309)
    static let warningDark  = Color(hex: 0xFBBF24)
    static let errorLight   = Color(hex: 0xB91C1C)
    static let errorDark    = Color(hex: 0xF87171)

    // MARK: 论坛原生语义色
    /// 收藏金（★ 收藏、◆ 积分 共用金色系）。
    static let accentGoldLight = Color(hex: 0xF5A623)
    static let accentGoldDark  = Color(hex: 0xFFC861)
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

    static func appGold(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? AppTheme.accentGoldDark : AppTheme.accentGoldLight
    }
}

// MARK: - 统一卡片容器
extension View {
    /// 圆角卡片：底色 + 圆角 + 一圈 0.5px 细描边。
    ///
    /// **为什么需要描边**：浅色模式下页面底色与卡片底色同为纯白（`#FFFFFF`），
    /// 卡片边界完全看不出来（暗色下卡片是 `#161616`、背景是纯黑，本来就有对比）。
    /// 描边用既有的 `appBorder`（浅 `#DDD8E8` / 深 `#333333`），保持「扁平、无阴影」的设计语言。
    func appCard(_ scheme: ColorScheme, cornerRadius: CGFloat = 16) -> some View {
        self
            .background(Color.appSurface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.appBorder(scheme), lineWidth: 0.5)
            )
    }
}
