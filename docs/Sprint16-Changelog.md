# Sprint 16 Changelog（2026-09-20）

本轮把「用户之间能做的六件事」从**死按钮/本地假象**改成**真调论坛接口 + 回读确认**，
并第一次打通**附件一次性 multipart 上传**。

范围由用户拍板：五项功能（加好友 / 拉黑 / 收藏 / 站内分享 / 举报）+ 附件上传。

---

## 〇、先纠两个事实（用户提供的真实链接）

| 功能 | 结论 | 依据 |
|---|---|---|
| 加好友 / 好友列表 / 删好友 | **真实存在** | `my.php?item=buddylist&newbuddyid=<uid>&buddysubmit=yes`（加）<br>`my.php?item=buddylist`（列表）<br>`my.php?item=buddylist&action=delete&friendid=<uid>&buddysubmit=yes`（删） |
| 搜贴（按作者） | **真实存在** | `search.php?srchuid=<uid>&srchfid=all&srchfrom=0&searchsubmit=yes` |
| 收藏 | **真实存在** | 加入 `my.php?item=favorites&type=thread` 自己的收藏列表 |
| 分享 | **只能站内分享** | 分享给好友（站内短信） |
| 举报 | 站内无原生入口 | 改为「复制帖子链接 → 私信管理员」 |
| 拉黑（用户互拉） | **论坛无此功能** | 按用户建议做成**本地屏蔽** |

> 上一轮我把它当成「死按钮」是错的——是我的探查没到位，不是论坛没有。

### 重要语义纠偏：两种「隐藏」不是一回事

用户明确指出，必须区分：

| | 本地拉黑（用户行为） | 论坛处罚（管理员行为） |
|---|---|---|
| 数据源 | 本地 `BlockedUser`（SwiftData） | 服务端 `Post.isBlocked` |
| 触发者 | 用户自己 | 论坛管理员 |
| 文案 | **`-已拉黑-`** | 该帖已被论坛隐藏 |
| 能否取消 | **可以**（占位里带「取消拉黑」） | 不能（无开关） |
| 图标 | `nosign` | `eye.slash` |

Sprint 15 的初版把两者混用同一 `isBlocked` 标志，本轮拆开成两条独立链路。

---

## 一、用户卡三键真实化（Task #137）

`Shared/UserCardSheet.swift`（+90 行）三键不再为空闭包：

- **加好友 / 删好友**：新增 `Repositories/BuddyRepository.swift`（138 行）
  - `buddies()` 复用 `MySpaceParser.parse(kind: .friends)`，不重复造解析器；
  - `isBuddy(uid:)` 进卡时先查列表，决定显示「加好友」还是「删好友」；
  - `add` / `remove` 走上面两条真实 URL，**每次变更后回读好友列表确认**，不符返回 `.unconfirmed`。
- **搜贴**：`SearchRepositoryProtocol` 新增 `search(authorUID:)` → `SearchViewModel.search(authorUID:)`
  → 打开 `SearchResultsView(authorUID:authorName:)`。失败文案「没有搜到该用户的主题」（不假装有结果）。
- **拉黑 / 取消拉黑**：写本地 `BlockedUser`；未登录 → 弹登录入口。

**未登录一律先弹登录**（见 §五 权限口径）。

---

## 二、拉黑占位三处统一（Task #138）

新增 `Shared/BlockedPlaceholderRow.swift`（58 行）——统一占位组件，内含「取消拉黑」按钮。

- `Features/Forum/ThreadListView.swift`：**不再把被拉黑作者的主题从列表里删掉**，
  改为渲染占位行。原做法会让列表「凭空少几条」，用户会以为丢数据。
  新增 `blockedUIDs` 计算属性；长按菜单文案「屏蔽」→「拉黑」。
- `Features/Home/HomeView.swift`：`feedList` 的 `ForEach` 包 `Group` 分支，同样渲染占位。
- `Features/Thread/PostContent.swift`：`init` 增 `onUnblock` 回调；
  body 里**本地拉黑**与**论坛处罚**彻底分叉（见 §〇 表格）。楼层里也能取消拉黑。

---

## 三、真实收藏（Task #139）

新增两个文件：

- `Repositories/FavoriteRepository.swift`（189 行）
  - `favorites()` 复用 `MySpaceParser.parse(kind: .threads)`（**服务器列表是唯一判据**）；
  - `add(tid:)` / `remove(tid:)`：先读列表拿 `formhash` 与现有集合，
    再按 Discuz 的**多种候选 URL 依次尝试**，**每次回读列表确认**，全失败返回 `.unconfirmed`。
  - 为什么要多候选：真实帖子页里的收藏入口被模板整块 HTML 注释掉了（Sprint 15 已探明），
    所以只能防御式穷举 + 回读确认，**不乐观更新、不谎报成功**。
- `Core/FavoritesStore.swift`（77 行）：`@MainActor ObservableObject` 单例，
  `tids` / `items` / `isLoading` / `lastError`；`toggle(tid:)` 失败返回 `nil`。

接入点：

- `HomeView` / `SearchResultsView` 的收藏态改读 `FavoritesStore.shared.tids`，
  `toggleSave` 改走服务器；未登录 `showLogin = true`。
- `Features/Profile/SavedThreadsView.swift` **整体重写**：读服务器收藏列表，未登录显示登录入口，
  下拉刷新，滑动取消收藏。删掉原先的本地列表逻辑。
- `Models/LocalModels.swift`：`SavedThread` 标记 **[已弃用]**，
  仅保留模型定义以稳定 SwiftData schema（删字段会触发迁移风险）。

---

## 四、站内分享 + 举报（Task #140）

- 新增 `Shared/ShareToBuddySheet.swift`（168 行）：
  读 `BuddyRepository.buddies()` → 选好友 → `PMRepository.send(uid:message:)` 发私信（标题 + 帖子链接）。
  空列表 / 需登录 / 发送失败**如实呈现**，不弹「已发送」。
- `Features/Thread/PostDetailRow.swift`：操作栏「分享」由单按钮改为 `Menu`
  （**系统分享** / **分享给好友**）；新增「举报」按钮（`exclamationmark.bubble`）。
- `Features/Thread/ThreadDetailView.swift`：接 `showShareToBuddy` / `showReportChat` 两个 sheet；
  `reportThread()` = 复制帖子链接 + 打开给管理员的 `MessageChatView`；
  收件人 UID 来自 `Shared/PreferenceStore.swift` 新增的 `reportAdminUID` 配置项。
- `toggleSaveThread()`：走服务器收藏，结果以**回读**为准。

> ⚠️ **待补**：`reportAdminUID` 默认 `0`，未配置时举报只复制链接并提示。
> 需要用户提供「举报管理员的 UID」后填入。

---

## 五、附件 multipart 上传（Task #141）

原理：**Discuz 的发帖页本身就是一个可带文件的表单**——先 GET 解析出 hidden 域 + file 域 + formhash，
再**一次性 POST 提交**（正文和文件在同一个请求里），不需要先传文件再拿 ID。

- `Parsers/DiscuzFormParser.swift`（+70 行）
  - `Form` 增 `fileFieldNames` / `isMultipart`；`parse` 增 `fileInputNames(in:)` / multipart enctype 检测；
  - 新增 `MultipartFile` 结构、`makeBoundary()`、`multipartBody(boundary:fields:files:)`：
    **文本字段用 GBK 编码**（论坛 `charset=gbk`，UTF-8 会把中文存成乱码，Sprint 7C 已验证），
    **文件名也用 GBK**，**文件内容按二进制原样写入**，收尾 `--boundary--`。
- `Repositories/PostRepository.swift`（+41 行）
  - 新增 `PostAttachment` 结构；`submitNewThread(..., attachments:)`；
  - `submit` 内分支：**无附件** → `gbkFormURLEncoded`；**有附件** → `multipartBody`
    （文件域字段名优先用运行时解析到的，解析不到退回 Discuz 惯用名 `attach[]`）。
- `Features/Compose/NewPostView.swift`（+176 行）
  - `PhotosPicker`（图片）+ `fileImporter`（任意文件）；`attachmentStrip` 预览条；
    `loadPickedPhotos` / `handleFileImport` / `mimeType(for:)`；新增 `DraftAttachment`；
  - **删掉原来的 `attachButton` 死按钮**（原来是 `notice = "尚未接入"`）。

---

## 六、权限口径（用户拍板，本轮起生效）

> 游客**只**浏览能浏览的版块即可；**其余操作一律要求登录**。

- 所有写操作（加好友/删好友/收藏/分享/举报/发帖/回帖/拉黑同步）**先查登录态**，
  未登录 → 弹登录入口，不执行、不假装成功。
- 统一从 `SessionManager.shared.state.isAuthenticated` 判定。

---

## 七、静态体检

- `analysis/swiftcheck.mjs`：**5 个 BAD，全部为已知 raw string（`#"…"#`）误报**
  （`PostContent` / `DiscuzFormParser` / `ThreadImageParser` / `PostRepository` / `ReplyRepository`），
  与本次改动无关（已 `grep -c '#"'` 确认确有 raw string）。
- `analysis/dups.mjs`：本轮 11 个新符号各声明一次，**无重名**。

---

## 八、改动规模

- 修改 17 个文件（+814 / −169）；
- 新增 5 个源文件：`FavoritesStore` / `BuddyRepository` / `FavoriteRepository` /
  `BlockedPlaceholderRow` / `ShareToBuddySheet`；
- `docs/FeatureStatus.md` 由 Sprint 15 整理时新建，本轮一并入库。

---

## 九、截图验收（本轮 6 界面 × 亮暗 = 12 张）

`D4D4YClientScreenshots/AppScreenshotTests.swift` 的 `targets` 已改：

| # | screen | 验收点 |
|---|---|---|
| ① | `home` | 被拉黑作者的主题显示「-已拉黑-」占位 |
| ② | `thread` | 操作栏分享菜单（系统分享 / 分享给好友）+ 举报按钮 |
| ③ | `userCard` | 加好友 / 搜贴 / 拉黑 三键真实化 |
| ④ | `newPost` | 发帖页图片 / 附件选择与预览条 |
| ⑤ | `savedThreads` | 我的收藏改为服务器列表 |
| ⑥ | `replyPlaceholder` | 上轮未验收：占位符输入框补可见边界 |

---

## 十、已知风险 / 待办

1. **附件字段名与提交权限需真机登录验证**：游客拿不到发帖页结构，
   `attach[]` 是兜底猜测；若服务端拒绝，需按真机解析到的 file 域名修正。
2. **收藏的候选 URL 需真机确认**：帖子页入口被模板注释，多候选是防御式方案，
   真机登录后应确认哪条命中，并删掉无效候选。
3. **举报管理员 UID 待填**（`PreferenceStore.reportAdminUID`）。
4. 用户可提供**体验账号**用于页面结构探查；届时只用于看结构，
   **不写代码、不提交 git、不打印凭据**（建议直接给另存的 HTML 以避免提供密码）。
