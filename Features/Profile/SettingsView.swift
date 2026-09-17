import SwiftUI
import SwiftData

/// 阅读设置。
/// - 外观（主题模式）：system / light / dark。
/// - 字号：小 / 标准 / 大。
/// - 行距：紧凑 / 标准 / 宽松。
/// - 列表密度：紧凑 / 标准 / 宽松（影响列表行与楼层的纵向间距）。
///
/// 所有值持久化到本地 `LocalSettings`（SwiftData 单例），正文与列表实时联动。
struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [LocalSettings]

    private let modes: [(String, String)] = [
        ("system", "跟随系统"),
        ("light", "浅色"),
        ("dark", "深色")
    ]

    // 字号预设
    private let fontPresets: [(String, Double, String)] = [
        ("small", 15, "小"),
        ("standard", 17, "标准"),
        ("large", 19, "大")
    ]
    // 行距预设（系数）
    private let spacingPresets: [(String, Double, String)] = [
        ("compact", 1.35, "紧凑"),
        ("standard", 1.5, "标准"),
        ("comfortable", 1.7, "宽松")
    ]
    // 列表密度
    private let densityPresets: [(String, String)] = [
        ("compact", "紧凑"),
        ("normal", "标准"),
        ("comfortable", "宽松")
    ]

    var body: some View {
        List {
            Section("外观") {
                if let setting = settings.first {
                    Picker("主题", selection: Binding(
                        get: { setting.themeMode },
                        set: { newValue in
                            setting.themeMode = newValue
                            try? setting.modelContext?.save()
                        }
                    )) {
                        ForEach(modes, id: \.0) { key, label in
                            Text(label).tag(key)
                        }
                    }
                    .pickerStyle(.segmented)
                } else {
                    Text("设置未初始化")
                        .foregroundStyle(Color.appTextTertiary(scheme))
                }
            }

            Section("阅读") {
                if let setting = settings.first {
                    // 字号
                    Picker("字号", selection: fontBinding(for: setting)) {
                        ForEach(fontPresets, id: \.0) { key, value, label in
                            Text(label).tag(key)
                        }
                    }
                    .pickerStyle(.segmented)

                    // 行距
                    Picker("行距", selection: spacingBinding(for: setting)) {
                        ForEach(spacingPresets, id: \.0) { key, value, label in
                            Text(label).tag(key)
                        }
                    }
                    .pickerStyle(.segmented)

                    // 列表密度
                    Picker("列表密度", selection: Binding(
                        get: { setting.listDensity },
                        set: { newValue in
                            setting.listDensity = newValue
                            try? setting.modelContext?.save()
                        }
                    )) {
                        ForEach(densityPresets, id: \.0) { key, label in
                            Text(label).tag(key)
                        }
                    }
                    .pickerStyle(.segmented)
                } else {
                    Text("设置未初始化")
                        .foregroundStyle(Color.appTextTertiary(scheme))
                }
            }
        }
        .navigationTitle("阅读设置")
        .scrollContentBackground(.hidden)
        .background(Color.appBackground(scheme))
    }

    // MARK: - 预设 → 数值 绑定

    /// 字号：以当前 `fontSize` 就近匹配预设 key；切换时写回对应数值。
    private func fontBinding(for setting: LocalSettings) -> Binding<String> {
        Binding(
            get: {
                let v = setting.fontSize
                return v <= 15 ? "small" : (v >= 19 ? "large" : "standard")
            },
            set: { key in
                if let p = fontPresets.first(where: { $0.0 == key }) {
                    setting.fontSize = p.1
                    try? setting.modelContext?.save()
                }
            }
        )
    }

    /// 行距：以当前 `lineSpacing` 就近匹配预设 key；切换时写回对应系数。
    private func spacingBinding(for setting: LocalSettings) -> Binding<String> {
        Binding(
            get: {
                let v = setting.lineSpacing
                return v <= 1.4 ? "compact" : (v >= 1.65 ? "comfortable" : "standard")
            },
            set: { key in
                if let p = spacingPresets.first(where: { $0.0 == key }) {
                    setting.lineSpacing = p.1
                    try? setting.modelContext?.save()
                }
            }
        )
    }
}
