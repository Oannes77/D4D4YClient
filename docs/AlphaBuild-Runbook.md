# D4D4YClient — Alpha Build Phase 1 运行手册 / 构建报告模板

> 阶段目标：**建立第一次真实 Xcode 15.4 + iOS 17 编译基线**，只求 `BUILD SUCCEEDED`。
> 不接入：TestFlight / App Store Connect / 签名 / fastlane / 开发者账号。
> 暂停新功能：收藏 / 搜索 / 发帖 / 通知。

---

## 0. 当前就绪状态（由 WorkBuddy 在 Windows 完成）

- ✅ Windows 静态预检完成 → 见 `docs/AlphaBuild-Preflight.md`（5 个编译风险区 + schema 风险结论）
- ✅ Git 仓库已 `git init` + `.gitignore` + `.gitattributes` 就位，源码已全部 stage
- ✅ `codemagic.yaml` 为 **alpha-build** workflow：仅
  `xcodegen generate` → `xcodebuild build`(Simulator) → `xcodebuild test`
  Phase 2（签名/TestFlight）已整段注释，**零密钥即可跑**

> ⚠️ **诚实边界**：WorkBuddy 运行在 Windows，无 Xcode，**无法产出真实 build log**。
> 真实构建必须在 Codemagic 云端 Mac 触发，下方为完整操作手册与报告模板。

---

## 1. 触发第一次真实构建（你来执行）

1. 在 GitHub 新建空仓库（建议名 `D4D4YClient`，**不要**勾选初始化 README/.gitignore）
2. 本地推送：
   ```bash
   git remote add origin <你的仓库URL>
   git branch -M main
   git push -u origin main
   ```
3. 登录 https://codemagic.com → **Add application** → 选择该 GitHub 仓库
   → 自动检测到 `codemagic.yaml`，workflow = `alpha-build`
4. 点击 **Start new build**（**不要配置任何环境变量 / 密钥**）
5. 等待约 5–15 分钟（brew 装 XcodeGen + SPM 拉 SwiftSoup + 编译）

---

## 2. 必须收集的输出（来自 Codemagic Build log）

| 输出项 | 在 log 哪里找 | 期望 |
|---|---|---|
| **Xcode 版本** | 构建开头环境信息 / `xcodebuild` 第一行 | `15.4` |
| **Swift 版本** | `swift --version` 或 build 日志顶部 | `5.9.x`（Xcode 15.4 自带）|
| **xcodegen 结果** | `Generate Xcode project` step | 无 error，生成 `D4D4YClient.xcodeproj` |
| **SPM 依赖解析** | build 日志中 `Resolving package graph` / `SwiftSoup` | `SwiftSoup` 解析成功（CI 用 2.x）|
| **build log** | `Build for iOS Simulator` step 完整输出 | 末行 **`BUILD SUCCEEDED`** |
| **test 结果** | `Run unit tests` step | 见第 3 节 |

> 把以上 6 项直接贴回对话，WorkBuddy 据此做错误分类与修复。

---

## 3. Test 步骤说明

- `Tests/D4D4YClientTests.swift` 当前若为空 / 无用例，`xcodebuild test` 可能报 `no tests found`，
  但 **build 仍 SUCCEEDED**。`codemagic.yaml` 已用 `set +e` 容错，不阻断流水线。
- **Phase 1 成功标准仅要求 `BUILD SUCCEEDED`**；test 通过为加分项，不强求。
- 若日后补了真实 XCTest 用例且失败，按第 4 节 **E 类（运行时错误）** 处理。

---

## 4. 错误分类（若失败：先分类，再逐项修，不要盲改）

| 类别 | 典型表现 | 排查入口 |
|---|---|---|
| **A. Swift 编译错误** | `error: cannot find 'X' in scope`、`does not conform to`、`#Predicate` 捕获非法、`@Model` 存储属性类型非法（非 Codable/Sendable） | 文件名:行号，定位源码改 |
| **B. Xcode 配置错误** | `xcodegen` 失败（project.yml 语法/路径）、`scheme 'D4D4YClient' not found`、bundle id 冲突、deployment target 不支持某 API | `project.yml` / `codemagic.yaml` 环境段 |
| **C. SPM 依赖错误** | `SwiftSoup` 版本解析失败、与 Xcode 15.4 工具链不兼容、网络拉取超时 | `project.yml` 的 `packages:` / 网络 |
| **D. 代码兼容错误** | iOS 17 模拟器不支持的 API、弃用警告被升级为错误、`@available` 缺失 | 编译错误中 `API`/`unavailable` 字样 |
| **E. 运行时错误** | 启动崩溃、SwiftData 迁移崩溃、test 运行期 assert | 仅 test step；见第 5 节 |

**修复流程**：复制完整 error 文本 → 定位 文件:行 → Windows 本地用 Read/Grep 核对 → 改 → 重新 `git push` 触发 CI。

---

## 5. SwiftData schema 变化记录（本阶段只记录，不做 MigrationPlan）

源：`Models/LocalModels.swift`（共 **6 个 `@Model`**），`D4D4YApp` 用 `ModelContainer(for: …)` 且无版本化 `Schema`。

| 模型 | 状态 | 说明 |
|---|---|---|
| `PinnedForum` | 稳定 | Sprint 8 起未变 |
| `BlockedUser` | 稳定 | Sprint 8 起未变 |
| `ReadHistory` | ⚠️ **本周期改字段** | 新增 `lastReadPostID: Int?`（及更早 `forumID: Int?`）→ schema 变化 |
| `VisitedForum` | 稳定 | Sprint 8 起未变 |
| `LocalSettings` | 稳定 | Sprint 8 起未变 |
| `ThreadMediaCache` | ⚠️ **本周期新增** | Sprint 9B2 引入（9B 中名为 `ThreadImageCache`，属 model 重命名/新增）→ schema 变化 |

**风险**：若此前在真机/模拟器装过旧 build（含旧 `ReadHistory` 字段 或 `ThreadImageCache`），再装新包会因 schema 不匹配 **启动即崩溃**。
**缓解（用户要求：本阶段不做 MigrationPlan，仅用干净环境验证）**：
- CI 每次全新 boot 干净模拟器 → 不受旧 schema 影响
- 你本地真机调试时：**卸载 App / 重置模拟器** 后重装
- Phase 2 再引入 `MigrationPlan`（轻量本地模型可全量重建，成本低）

---

## 6. 成功标准

`BUILD SUCCEEDED`（Simulator, Debug）→ 即拿到 **第一次真实 macOS/Xcode 构建报告**（第 2 节 6 项）。

---

## 7. 拿到 BUILD SUCCEEDED 之后

- 可选：补真实 XCTest 用例（用 `Tests/Fixtures/` 验解析）
- 维持暂停：收藏 / 搜索 / 发帖 / 通知 不开发
- 视需要开 Phase 2：签名 + TestFlight 分发真机（届时再配 3 个 ASC 密钥）
