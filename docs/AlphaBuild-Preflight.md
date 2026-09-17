# D4D4YClient Alpha Build Phase 1 — 静态预检报告

> 目的：在 Windows 无 Xcode 环境下，对 Alpha Build 规格列出的 5 个编译风险区做**静态代码核查**，
> 提前产出「错误列表 + 修复计划」（规格输出 3、4）。
> Build log / Test 结果仍需 Codemagic 真机构建后取得。
>
> 判定基准：Swift 5.9 + Xcode 15.4 + iOS 17（与 codemagic.yaml 一致）。

## 一、核查范围与结论

| # | 风险区（规格点名） | 静态结论 | 说明 |
|---|---|---|---|
| A1 | SwiftData `@Model` / `@Query` / `#Predicate` | ✅ 未见编译错误 | 6 个 `@Model` 写法标准；`#Predicate { $0.fid == fid }` 仅捕获 `Int`/`String` 常量，符合 Xcode 15 对谓词捕获的要求 |
| A2 | SettingsView `ForEach` 闭包 | ✅ 未见编译错误 | 元组 `ForEach(modes, id: \.0) { key, label in }` 是标准写法；`\.0` 对元组元素的 KeyPath 合法，Xcode 15 可编译 |
| A3 | ReplyRepository GB18030 编码 | ✅ 未见编译错误 | `.gb_18030_2000` 在 Xcode 15 Foundation 中存在；`s.data(using:)` 用法正确 |
| A4 | HTMLContentView Swift 并发隔离 | ✅ Swift 5.9 无错（⚠️ 仅 Swift 6 模式需改） | `Task.detached` 仅捕获 Sendable 值（`ColorScheme`/`CGFloat`/`String`）；`.task` 内写 `@State` 在 Swift 5.9 仅警告不报错 |
| A5 | SwiftUI 状态管理 | ✅ 未见编译错误 | `@Query` / `@Environment` / `@EnvironmentObject`+单例混用是代码味道，不是编译错误 |
| B  | SwiftData schema 迁移 | ⚠️ 运行时风险（非编译） | 见第二节 |
| C  | SPM / SwiftSoup 2.7.0 | ✅ 兼容 Xcode 15.4 | 纯 Swift、iOS 11+，Swift 5.10 工具链兼容；CI 首次需联网拉 GitHub |

## 二、两条自定义符号疑点已排除

- `Color.appTextTertiary(_:)` — `DesignTokens.swift:140` 已定义（全工程 21 处调用）
- `UIColor(hex:)` — `DesignTokens.swift:18` 扩展已定义（`HTMLContentView` 使用）

## 三、⚠️ 唯一存活的真实风险：SwiftData schema 迁移（运行时，非编译）

- **现状**：`D4D4YApp` 使用 `ModelContainer(for: …)` 且**无版本化 `Schema` / `MigrationPlan`**。
- **含义**：
  - **首次在干净模拟器/真机运行**：无旧 store，自动建表 → 不崩溃。
  - **若你之前在某设备跑过旧 build**（`ReadHistory` 加过 `lastReadPostID`、新增 `ThreadMediaCache`），
    再装新 build 会因 schema 不匹配 **启动即崩溃**。
- **修复计划（开发期）**：
  1. 每次改了任一 `@Model` 字段 → 卸载 App / 重置模拟器后重装；或
  2. 后续引入 `Schema` 版本 + `ModelMigrationPlan`（轻量迁移）。**Phase 1 不做**。
- **对 Phase 1 编译**：无影响（CI 只编译，不运行 App）。

## 四、CI 才能真正确认的事（本静态检查替代不了）

1. **未列入上述 5 区的文件**是否有编译错误，只能靠真机构建：
   `ImageViewer` / `PostContent` / `PostHeader` / `PostCell` / `ReplyEditor` /
   `ReplyViewModel` / `ForumRepository` / 各 `Parsers` 等。
2. SwiftSoup 在 Xcode 15.4 下的实际 SPM 解析（联网拉 GitHub）。
3. `xcodegen generate` 是否因 `project.yml` 任何细节失败。

## 五、下一步（交给 Codemagic）

1. 把 `D4D4YClient` 作为仓库根推 GitHub（需 `.gitignore` 排除 `build/`、`.xcodeproj`）。
2. Codemagic 关联仓库，使用已瘦身的 `codemagic.yaml`（`alpha-build`：xcodegen + build + test，**零密钥**）。
3. 读 Build log：若出现第四节未覆盖文件的错误，逐条修；schema 崩溃属运行期，不在本阶段。
4. 成功标准：`BUILD SUCCEEDED`。
