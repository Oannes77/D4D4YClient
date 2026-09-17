# D4D4YClient Sprint 8 交付文档

> 阶段定位：真实 iOS 产品体验优化。本阶段不新增论坛功能（发帖 / 收藏 / 通知 / 私信 留待后续），
> 只打磨「浏览 + 回复」这条核心阅读链路，并把产品从 PoC 推进到接近正式第三方客户端的形态。

---

## 1. 真机编译结果

**环境约束**：当前为 Windows + 无 Xcode，无法在 Mac/iOS 上真正编译运行。以下为**静态编译审查结论**，
最终需在 Mac/Xcode（真机或模拟器）确认。

### 1.1 静态审查通过项

| 审查点 | 结论 |
|---|---|
| SwiftData | 5 个 `@Model`（`PinnedForum`/`BlockedUser`/`ReadHistory`/`VisitedForum`/`LocalSettings`）声明合规；`@Query` 全部处于 `RootView.modelContainer` 环境内；`ensureDefaultSettings()` 正确播种 singleton。未发现编译问题。 |
| AsyncImage | `AvatarView`、`PostContent.imagesGrid` 的 `AsyncImage` 三态（empty/success/failure）处理正确，无遗漏分支。 |
| NavigationStack | `RootView` 三 Tab → `HomeView`/`ForumListView` 内 `NavigationStack` → `.navigationDestination(for:)` 类型安全。 |
| safeAreaInset | `ThreadDetailView` 底部 `.safeAreaInset(edge: .bottom)` 融合 `ReplyEditor`，iOS 15+ 可用（部署目标 17）。 |
| Theme Token | 全项目统一走 `Color.app*(scheme)` / `LinearGradient`；无散落调色板（唯一 `Color.black` 在 `ImageViewer` 全屏看图灯箱，属合理黑底）。 |
| Keychain | `SecItem` 增/删/改/查 API 用法正确；`service` 由 `com.poc.d4d4yclient.auth` 改为 `com.d4d4y.client.auth`。 |
| Bundle ID | `project.yml` `bundleIdPrefix` 由 `com.poc` 改为 `com.d4d4y.client`；`Log` subsystem 同步。 |

### 1.2 需在 Mac/Xcode 真机确认的项（无法在 Windows 验证）

1. `ReplyRepository` 使用的 `.gb_18030_2000` 字符串编码在目标 iOS 上是否可用（GBK 编码，Sprint 7C 引入）。
2. `SettingsView` 中 `ForEach` 对元组元素 `(String,String)` / `(String,Double,String)` 的多参解构闭包是否如期编译（语法上合法，但建议真机确认）。
3. `HTMLContentView` 用 `NSAttributedString` HTML 导入在后台线程的执行与 `UITextView` 渲染一致性。
4. **Cloudflare**：脚本/模拟器 UA 可能被拦截；真实 iOS 设备原生网络请求预期可通过（Sprint 7B/7C 已用真实登录态验证过接口）。

---

## 2. 页面截图

⚠️ 当前环境无模拟器/真机，**无法生成真实页面截图**。请在 Mac/Xcode 运行后补截图。
建议截图页面：首页（常用板块/最近浏览/最近访问板块）、板块列表、主题列表（ThreadList）、帖子详情（ThreadDetail 含楼层与底部回复栏）、阅读设置页（浅色/深色各一张）。

---

## 3. UI 调整列表

### 3.1 Avatar（已确认真实接口）
- **错误假设修正**：早期 `AvatarView` 用 `uc_server/avatar.php?uid=xxx` 动态脚本；经 Sprint 8 真实抓取 4D4Y 页面确认，实际是 **CDN 静态文件**：
  `https://img02.4d4y.com/forum/uc_server/data/avatar/{9位零填充UID，每3位斜杠}/{uid}_avatar_{small|middle|big}.jpg`
- 重写 `AvatarView`：按上述规则拼静态路径；`uid` 缺失/加载失败回退中性系统人形图标（`person.crop.circle.fill`），**禁止随机/真人头像**；圆形裁切。

### 3.2 HTMLContentView 暗色/亮色自适应（解决 HTML 覆盖 Theme）
- 注入随 `colorScheme` 切换的 CSS：透明背景、主题文字色（Light `0x1C1C1E` / Dark `0xFFFFFF`）、品牌紫链接色（Light `0x9B8BD4` / Dark `0xB69AE8`）、图片自适应宽度。
- 渲染后遍历属性串：链接保留品牌紫，其余统一重写为主题文字色，覆盖论坛自带 `<font color>` / 行内样式。
- 字号 / 行距取自 `LocalSettings`（与「阅读设置」联动），保留加粗 emphasis。

### 3.3 阅读体验优化（ThreadList / ThreadDetail）
- **主题列表（最重要页面，Apple Mail + 论坛 风格）**：
  - 标题字号 `.subheadline` → `.body` 半粗，更清晰可读；行高 2 行。
  - 作者信息层级：作者名 `.caption` 半粗（次级色）/ 时间 `.caption2`（三级色），形成明确主次。
  - 回复数：改用线性 `bubble.right` 图标 + 计数，弱化色块，不再用 `message` 实心图标。
  - 头像 40 → 42，阅读更舒适。
  - 行间距随「列表密度」设置联动（紧凑 4 / 标准 8 / 宽松 12）。
- **帖子详情（App 灵魂）**：
  - 标题 `.headline` → `.title3` 半粗。
  - 楼层结构保持：头像 + 用户名 + 时间 + `#楼层` + 正文 + 图片，纯 `Divider` 分隔无 Card。
  - 楼层纵向间距随「列表密度」联动（紧凑 6 / 标准 10 / 宽松 14）。
  - 图片比例：缩略图统一 `height: 120`、`scaledToFill` + 圆角 8，避免超大图破坏节奏。

### 3.4 阅读设置（新增可联动）
- `SettingsView` 提供：外观（system/light/dark 分段）、字号（小 15 / 标准 17 / 大 19）、行距（紧凑 1.35 / 标准 1.5 / 宽松 1.7）、列表密度（紧凑/标准/宽松），全部写入 `LocalSettings`（SwiftData 单例）。
- 正文（`HTMLContentView`）实时随字号/行距变化；列表/楼层间距随密度变化。

### 3.5 首页继续弱化
- 移除与「最近浏览」重复的「最近帖子」分区；首页仅保留：常用板块 / 最近浏览 / 最近访问板块，纯文字列表，无 Banner、无品牌展示页。

### 3.6 板块列表
- `ForumListView` 维持纯文字列表 + 左侧低存在感 `pin` 线性图标（已固定板块标记），无彩色方块/图片卡片。

### 3.7 标识清理
- `com.poc` → `com.d4d4y.client`（bundleId、Log subsystem、Keychain service 三处）。

---

## 4. 未解决问题

1. **无法真机编译/截图**：Windows 无 Xcode，编译结果与截图需用户 Mac/Xcode 补完（见 §1.2）。
2. **头像 CDN 路径假设**：基于真实页面样本推断的 9 位零填充规则；若 4D4Y 个别 uid 格式异常或 CDN 域变更，需微调 `AvatarView.avatarURL`。
3. **HTML 正文强调还原度**：`NSAttributedString` HTML 导入对复杂内联样式（如颜色背景、列表缩进）还原有限；当前已强制统一文字色与字号，emoji/引用块等仍依赖系统导入。
4. **Cloudflare**：模拟器/脚本可能被拦，真机原生请求预期通过，但需真机首跑验证登录态保持。
5. **下阶段顺序**（用户已确认，勿颠倒）：收藏 → 搜索 → 发帖 → 通知。先把「阅读 + 回复」打磨到像真正的 iOS App。

---

## 5. 红线未改

以下文件本阶段**未改动**（保持 Sprint 7 架构）：
- `Network/HTTPClient.swift`
- `Parsers/*`
- `Repositories/ForumRepository.swift`
- `Repositories/ReplyRepository.swift`
- `Core/Authentication/*`（仅 Keychain `service` 字符串变更，逻辑不变）
