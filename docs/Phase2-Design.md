# D4D4YClient Phase 2 产品设计与架构规划

> 文档状态：设计稿（待确认）
> 适用平台：iOS 17+ / SwiftUI / SwiftData / MVVM / async-await
> 约束红线：不开发登录、注册、回复、发帖、私信、收藏、通知；不绕过权限、验证码、Cloudflare。

---

## 0. 范围与边界

Phase 2 把 Phase 1/1.5 的 PoC（只读解析）升级为**可长期使用的论坛阅读客户端**。本阶段所有新增能力均为**本地增强**或**公开页解析**，不触碰任何服务器写操作、不新增身份认证。

| 保留 Phase 1 能力 | Phase 2 新增 | 明确禁止 |
|---|---|---|
| 菜单解析、主题列表、帖子详情、楼层、分页 | 一级导航、固定板块、作者头像、作者屏蔽、图片查看器、搜索、浏览历史、阅读设置 | 登录/注册/回复/发帖/私信/收藏/通知 |
| HTTPClient、GBK 解码、CF 检测、Fixture Tests | SwiftData 本地持久化、深浅模式、Design Token | 绕过权限 / 验证码 / Cloudflare |

---

## 1. 产品定位与核心体验

**定位**：简洁、高效、适合长期阅读的 4D4Y 原生论坛阅读器。

**不是**：社交媒体、内容推荐流、信息流、展示型 App。

**核心阅读闭环**（打开 App → 常用板块 → 浏览标题 → 读帖 → 看图 → 返回继续）：
1. 进入常看板块（首页固定 / 板块 Tab）。
2. 快速浏览主题标题（高密度列表，无卡片）。
3. 阅读帖子正文与图片。
4. 返回继续浏览。

**设计基调**：iOS 原生 / 文字优先 / 论坛阅读器风格。规避大量卡片、Banner、渐变、复杂动画、Dashboard、过度装饰。

---

## 2. 页面导航结构

### 2.1 一级导航（固定三个 Tab，不增减）

```
TabView
├── 首页 Home            (Features/Home)
├── 板块 Forums          (Features/Forums)
└── 我的 Profile         (Features/Profile)
```

导航栏全局可放置**搜索按钮**（首页、板块页生效），点击 present `SearchView`（模态）。

### 2.2 二级/三级导航树

```
首页 Home
├── 常用板块区（PinnedForums）
│   └── 点击板块 → ThreadListView(fid:)
├── 最近浏览区（ReadHistory）
│   └── 点击 → ThreadDetailView(tid:)
└── 最近访问板块区（VisitedForum）
    └── 点击板块 → ThreadListView(fid:)

板块 Forums
└── 层级列表（ForumMenuParser）
    ├── 父板块
    │   └── 子板块
    └── 点击任意板块 → ThreadListView(fid:)
    （长按：添加到首页 / 调整顺序 / 取消固定）

主题列表 ThreadListView(fid:)
└── 点击主题 → ThreadDetailView(tid:)
    （列表行长按：隐藏作者 / 进板区）

帖子详情 ThreadDetailView(tid:)
├── 楼层正文（图片点击）→ ImageViewer（全屏模态）
└── 底部分页：上一页 · 当前/总页 · 下一页

图片查看器 ImageViewer（模态，覆盖式）
└── 左右滑动 / 双指缩放 / 双击放大 / 缩略图条

搜索 SearchView（模态）
└── 搜索结果（主题/用户/板块）→ 对应列表/详情

我的 Profile
├── 游客模式状态条
├── 浏览历史 → ReadHistoryView
├── 阅读设置 → SettingsView（主题/字号/行距/密度）
├── 屏蔽作者 → BlockedUsersView（管理）
├── 清理缓存 → 动作
└── 关于 4D4Y → 静态页
```

> 搜索为**模态 present**，不占用一级 Tab；图片查看器为**覆盖模态**，不进入 Tab 层级。

---

## 3. Model 修改方案

### 3.1 分层原则（关键）

保持 Phase 1.5 的网络/解析/UI 分离，并明确两类模型职责不同：

- **网络值模型（struct，不可持久化）**：`ForumThread`、`Post`、`ForumSection`、`PageInfo` —— 由 Parser 产出，代表**一次性网络快照**。
- **本地持久化模型（SwiftData `@Model` class）**：`PinnedForum`、`BlockedUser`、`ReadHistory`、`LocalSettings` —— 代表**用户本地状态**。
- **视图聚合模型（运行时组合）**：`ForumThread` 上的 `isRead / isPinned / isBlocked` 是**派生属性**，由 ViewModel 在运行时将网络模型与 SwiftData 查询结果组合得到，**不写入网络模型、不持久化网络内容**。

> 理由：不把整页网络内容塞进 SwiftData，可避免隐私/缓存膨胀，也保持解析层纯净。

### 3.2 ForumThread 扩展（派生字段，非持久化）

```swift
struct ForumThread: Identifiable {
    let tid: Int
    let title: String
    let typeName: String?
    let authorName: String
    let authorID: Int?
    var avatarURL: URL?           // 由 authorID 构造，见 §3.3
    let replyCount: Int
    let createdAt: Date?
    // —— 以下为运行时派生，不入 SwiftData ——
    var isRead: Bool = false      // 由 ReadHistory 查询得到
    var isPinned: Bool = false    // 由 PinnedForum 查询得到
    var isBlocked: Bool = false   // 由 BlockedUser 查询得到
}
```

### 3.3 新增 ForumUser / 头像策略

```swift
struct ForumUser {
    let uid: Int
    let username: String
    let avatarURL: URL?
}
```

**头像 URL 规律（待验证）**：Discuz! 7.2 + UCenter 的标准头像接口为
`https://www.4d4y.com/uc_server/avatar.php?uid={uid}&size=middle`。
- Phase 2 接入时通过真实请求验证该地址是否返回有效图片。
- 若接口不可用 / 返回空 / 非图片 → 回退到 **App 内置中性占位头像**（通用人形剪影，**禁止拼装任何具体真人照片冒充真实用户头像**）。
- 匿名帖（`authorID == nil`）直接显示占位头像，不猜测。

### 3.4 Post 模型（沿用 Phase 1.5，阅读器增强）

`Post`（含一楼与回复楼）字段保持不变（`id` 用真实 pid + FNV-1a 确定性 fallback）。Phase 2 仅在其 `htmlContent` 渲染层增强：
- 抽取 `<img>` 的 `src` 形成 `imageURLs: [URL]`，供图片查看器使用；
- 抽取外链形成可点击 `linkURLs`；
- 保留原始 HTML 结构（引用、表情、附件不丢）。

---

## 4. SwiftData 本地存储方案

### 4.1 Schema（四个 `@Model`）

```swift
import SwiftData

@Model
final class PinnedForum {
    @Attribute(.unique) var fid: Int
    var name: String
    var sortOrder: Int
    init(fid: Int, name: String, sortOrder: Int) {
        self.fid = fid; self.name = name; self.sortOrder = sortOrder
    }
}

@Model
final class BlockedUser {
    @Attribute(.unique) var uid: Int
    var username: String
    var createdAt: Date
    init(uid: Int, username: String, createdAt: Date = .now) {
        self.uid = uid; self.username = username; self.createdAt = createdAt
    }
}

@Model
final class ReadHistory {
    @Attribute(.unique) var tid: Int
    var title: String          // 冗余存标题，便于历史列表不回查网络
    var lastReadTime: Date
    init(tid: Int, title: String, lastReadTime: Date = .now) {
        self.tid = tid; self.title = title; self.lastReadTime = lastReadTime
    }
}

@Model
final class LocalSettings {
    var themeMode: String       // "system" | "light" | "dark"
    var fontSize: Double        // pt，基础正文字号
    var lineSpacing: Double     // 倍数或 pt
    var listDensity: String     // "compact" | "normal" | "comfortable"
    init(themeMode: String = "system", fontSize: Double = 17,
         lineSpacing: Double = 1.5, listDensity: String = "normal") {
        self.themeMode = themeMode; self.fontSize = fontSize
        self.lineSpacing = lineSpacing; self.listDensity = listDensity
    }
}
```

### 4.2 容器与注入

- 在 `D4D4YApp` 创建 `ModelContainer(for: PinnedForum.self, BlockedUser.self, ReadHistory.self, VisitedForum.self, LocalSettings.self)`。
- 通过 `.modelContainer(...)` 注入环境；各 ViewModel 用 `@Query` 或 `ModelContext` 读写。
- **单例设置**：`LocalSettings` 仅一条记录，App 启动时若不存在则插入默认值；读写走主上下文。

### 4.3 各功能与 SwiftData 映射

| 功能 | 模型 | 读 | 写 |
|---|---|---|---|
| 固定板块（首页展示/排序） | PinnedForum | `@Query(sort: \.sortOrder)` | insert/delete/reorder |
| 作者屏蔽（列表隐藏/详情折叠） | BlockedUser | 内存 Set<Int> 缓存 | insert/delete |
| 浏览历史（最近浏览区） | ReadHistory | `@Query(sort: \.lastReadTime, order: .reverse)` | 进帖时 upsert |
| 最近访问板块（首页区） | VisitedForum | `@Query(sort: \.lastVisitedAt, order: .reverse)` | 进入板块时 upsert |
| 阅读设置（主题/字号/行距/密度） | LocalSettings | 单例读取 | 更新字段 |

### 4.4 屏蔽逻辑落地

- **主题列表**：ViewModel 加载后，过滤 `authorID ∈ BlockedUser.uid` 的主题（服务端数据不变，仅本地隐藏）。
- **帖子详情**：被屏蔽作者的楼层不删除，渲染为占位行「该作者内容已隐藏 · 点击查看」，点击可临时展开（不持久化解封）。
- **管理**：`BlockedUsersView` 列出并支持取消屏蔽。

### 4.5 认证状态框架（空架构，不实现登录）

> Sprint 1 建立**仅状态框架**，为后续登录阶段预留接口；当前不构成任何登录能力。

位置：`Core/Authentication/`

| 文件 | 职责 |
|---|---|
| `AuthenticationState.swift` | `enum AuthenticationState { case guest; case authenticated(UserSession) }`，当前唯一合法值为 `.guest` |
| `UserSession.swift` | 已登录会话的本地数据容器（uid / username / loginTime），当前不构造实例 |
| `SessionManager.swift` | `@MainActor ObservableObject`，持有并发布 `state`；`shared` 单例已注入根视图环境。**预留 `signIn` / `signOut`，本阶段不实现** |

约束：

- 禁止在此阶段伪造 `.authenticated` 状态、禁止缓存明文密码、禁止绕过验证码 / Cloudflare。
- 登录实现须走真实论坛登录接口，且需用户明确授权后于后续阶段开发。
- **凭据存储边界**：SwiftData 仅保存上述 5 个本地状态模型（PinnedForum / BlockedUser / ReadHistory / VisitedForum / LocalSettings）。未来登录凭据（如 session cookie、token）**不进入 SwiftData**，改为存入系统 Keychain；Keychain 访问层在登录阶段单独实现。

---

## 5. UI Design Token

### 5.1 Light Mode

| Token | 用途 | 值 |
|---|---|---|
| `colorPrimary` | 主色（芋艿紫） | `#6F4BA8` |
| `colorPrimarySoft` | 浅紫（选中/高亮底） | `#EEE8F7` |
| `colorBackground` | 背景 | `#F8F7FA` |
| `colorSurface` | 卡片/行底（列表行也可用） | `#FFFFFF` |
| `colorTextPrimary` | 主文字 | `#1C1C1E` |
| `colorTextSecondary` | 次要文字（作者/时间/回复数） | `#8A8890` |
| `colorDivider` | 分割线 | `#E5E5EA` |

### 5.2 Dark Mode

| Token | 用途 | 值 |
|---|---|---|
| `colorPrimary` | 主色 | `#B69AE8` |
| `colorBackground` | 背景 | `#17131F` |
| `colorSurface` | 表面 | `#241D30` |
| `colorTextPrimary` | 主文字 | `#FFFFFF` |
| `colorTextSecondary` | 次要文字 | `#AAA0B8` |

### 5.3 令牌落地方式

- 定义 `enum ThemeToken` + `Color` 扩展，按 `colorScheme` 返回对应值；或使用 `ColorSet` asset 让系统在 Light/Dark 自动切换（推荐 asset，零运行时成本）。
- 主题切换由 `LocalSettings.themeMode` 驱动：`.environment(\.colorScheme, ...)` 或 `preferredColorScheme`。`system` 跟随系统。

### 5.4 排版与密度

- 基础正文 `fontSize`（默认 17pt，可在设置调节 15–21）。
- 列表密度 `listDensity` 控制行高/内边距：`compact` 更紧、`normal` 标准、`comfortable` 宽松。
- 行距 `lineSpacing` 应用于帖子正文 `AttributedString`。

---

## 6. SwiftUI 页面拆分方案

保持 `Features/<Domain>/<View>.swift + <ViewModel>.swift` 结构，新增 `Search`、`Profile` 域；Parser/Repository/Network 不动（仅按需扩展）。

```
Features/
├── Home/
│   ├── HomeView.swift
│   └── HomeViewModel.swift            // 聚合 PinnedForums + VisitedForum + ReadHistory
├── Forums/
│   ├── ForumListView.swift            // 层级列表（ForumMenuParser 数据）
│   └── ForumListViewModel.swift       // 含长按固定/排序
├── Thread/
│   ├── ThreadListView.swift           // 高频页：无卡片阅读布局 + 头像 + 屏蔽过滤
│   ├── ThreadListViewModel.swift      // 已含分页（复用 Phase 1.5）
│   ├── ThreadDetailView.swift         // 阅读器布局
│   ├── ThreadDetailViewModel.swift
│   ├── ImageViewerView.swift          // 全屏查看器（独立模态）
│   └── HTMLContentView.swift          // 已有，增强图片/链接抽取
├── Search/
│   ├── SearchView.swift               // 模态搜索入口 + 结果
│   └── SearchViewModel.swift          // 解析论坛搜索页（待验证 URL）
└── Profile/
    ├── ProfileView.swift
    ├── ProfileViewModel.swift
    ├── ReadHistoryView.swift
    ├── SettingsView.swift             // 主题/字号/行距/密度
    └── BlockedUsersView.swift         // 屏蔽管理

Shared/
├── DesignTokens.swift / Assets.xcassets   // §5 令牌
├── Loadable.swift                        // 已有
├── Log.swift                             // 已有
└── HTMLDecoder.swift                     // 已有
```

**关键 UI 规则**：
- 主题列表**禁用 Card**，用 `List`/自定义 `HStack` 行 + `Divider`，头像左、标题+元数据右。
- 帖子详情用 `ScrollView` + `VStack` 楼层块，底部固定分页条。
- 图片查看器用 `TabView(style: .page)` + `MagnificationGesture`/`onTapGesture`（双击），缩略图条横向 `ScrollView`。
- 搜索结果复用 `ThreadListView` / `ForumListView` 的单元格组件，避免重复。

---

## 7. 开发 Sprint 计划

### Sprint 1 — App Shell（导航 + 主题）
- TabView 三栏（首页/板块/我的）。
- 接入 `DesignTokens` + `Assets.xcassets` 明暗色板。
- `LocalSettings` 单例 + `preferredColorScheme` 切换。
- 占位首页/板块/我的骨架（数据仍接 Phase 1.5 Parser）。

### Sprint 2 — 固定板块
- `PinnedForum` SwiftData 模型 + 容器注入。
- 板块页长按：添加/取消固定/排序。
- 首页「常用板块」区展示与跳转。

### Sprint 3 — 主题列表（最高频）
- 接入 `ThreadListParser` + 分页（复用 Phase 1.5）。
- 作者头像（§3.3 规律 + 默认占位，待验证接口）。
- 显示：头像/标题/作者/回复数/时间；**禁止**浏览量、等级、积分、注册时间。
- 作者屏蔽：列表过滤 + `BlockedUsers` 管理入口。

### Sprint 4 — 帖子详情 + 图片
- 楼层渲染（§3.4 抽取图片/链接）。
- 图片查看器（全屏/滑动/缩放/缩略图）。
- 阅读设置（字号/行距）实作用于正文。
- 底部分页（上一页/当前总页/下一页）。
- 被屏蔽作者楼层折叠为「已隐藏 · 点击查看」。

### Sprint 5 — 预留
- 搜索功能已在 Sprint 3 一并规划接口；具体解析与结果页在 Sprint 3 实现。

> 每个 Sprint 完成后均可独立运行验证；Fixture Tests（Phase 1.5）持续保障 Parser 不被破坏。

---

## 8. 已知技术风险 / 待验证项（诚实区分）

1. **头像接口未验证**：`uc_server/avatar.php?uid=` 是否对该站有效需在 Sprint 3 用真实请求确认；无效则一律占位头像。
2. **搜索 URL 未验证**：Discuz! 7.2 搜索页路径/参数（`search.php?srchtxt=...`）需先抓真实搜索页再定 selector，禁止假设。
3. **SwiftData 在 iOS 17 行为**：`@Query` 跨视图注入、`ModelContext` 主线程写需实编确认；当前 Windows 环境**无法编译验证**，仅静态规划。
4. **SwiftSoup 渲染 HTML 图片**：正文 `<img>` 可能是相对路径或带 `attach` 参数，需补充 URL 归一化（绝对化到 `4d4y.com/forum/`）。
5. **CF 不确定性**：若 Cloudflare 扩大质询范围，公开页读取将受阻（按约束不绕过），需在 Sprint 1 即埋点监控。
6. **WAP 模板改版风险**：定制模板若换版，所有 selector 需随 Fixture Tests 快速回归。

---

## 9. 验收（Phase 2 完成后预期）

- 三 Tab 导航可用，明暗模式正确切换。
- 可固定/排序常用板块并在首页展示。
- 主题列表为高密度阅读布局，含真实头像、回复数、时间，无禁显字段。
- 作者屏蔽在列表与详情均生效且不删数据。
- 帖子详情可读楼层、看图、分页。
- 搜索能解析真实搜索结果（待验证链路）。
- 浏览历史、阅读设置、清理缓存、关于页可用。
- **全程无登录/写操作代码，无权限绕过。**
