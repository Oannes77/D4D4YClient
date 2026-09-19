# Sprint 10：从演示数据走向真实论坛（首页 / 板块 / 搜索 / 发帖）

> 目标：本轮之前，首页与搜索、发帖都还是离线样例；本轮把**首页板块流、板块管理、搜索、发帖**全部接到真实论坛接口，
> 演示模式（`-DemoMode`）仍走离线样例，保证 Codemagic 截图不受影响。

## 一、做了什么

### 1. 首页接真实数据（核心）
- `Features/Home/HomeViewModel.swift`（重写为网络驱动）
  - 板块来自 SwiftData `PinnedForum`（用户顺序），主题流来自 `ForumRepository.threads(fid:page:)`。
  - 支持下拉刷新（`.refreshable`）、滚到末尾自动加载下一页（分页 URL 由 `PaginationParser` 解析给出，不自行拼接）。
  - 加载 / 空 / 失败三态；失败页给「重试」。
  - 首图 / 附件 / **首帖预览文本**由 `ImageMetadataRepository` 延迟检测（只检测未缓存的，最多 20 条，结果入 `ThreadMediaCache`，24h）。
- `Features/Home/HomeView.swift`
  - 板块切换条改为 fid 驱动（`BoardChipItem`），选中即记录 `VisitedForum`。
  - 搜索栏回车 → `SearchResultsView`；FAB → 发帖页（默认发布到当前板块）。
  - Demo 模式仍注入 `DemoData.homeFeedDemo()`，不联网。
- `Shared/BoardChips.swift`：标识由「板块名」改为「fid」，避免重名混淆。
- `Shared/CollapsibleSearch.swift`：新增 `placeholder` 与回车 `onSubmit`。

### 2. 板块管理持久化 + 真实板块列表
- `Features/Profile/BoardManageView.swift`
  - 已选板块 = `PinnedForum`（SwiftData），排序 / 增删即时持久化。
  - 「可添加板块」优先取论坛真实板块（`ForumRepository.sections`），失败或演示模式回退内置常用板块。
  - 右上角刷新按钮可重新拉取论坛板块。
- 新增 `Shared/ForumBoards.swift`：内置常用板块真实 fid 清单（首页默认 / 板块管理兜底 / 发帖页共用）。

### 3. 搜索接真实接口
- 新增 `Repositories/SearchRepository.swift`：`search.php?srchtxt=<GBK>&srchtype=title&searchsubmit=yes`。
- 新增 `Parsers/SearchResultParser.swift`：两级解析（先复用板块列表结构 `tr:has(td.listcon)`，再兜底通用抽取 `viewthread.php?tid=` 链接）。
- 新增 `Features/Home/SearchViewModel.swift`；`SearchResultsView` 改为 ViewModel 驱动。
- 游客态实测返回「您还未登录，无法进行此操作」→ 明确提示「搜索需要登录」，不伪造结果。

### 4. 发帖接真实接口
- 新增 `Parsers/DiscuzFormParser.swift`：回复 / 发帖共用的表单解析与 GBK 编码工具（不硬编码任何 POST 参数）。
- 新增 `Repositories/PostRepository.swift`：`post.php?action=newthread&fid=` 动态解析表单 → GBK POST 提交 → 复查板块列表确认标题出现。
- `Features/Compose/NewPostView.swift`：板块取自 `PinnedForum`（未配置用内置板块），标题留空自动取正文首行，发布走真实提交并显示结果。

### 5. 数据模型微调
- `ThreadMediaInfo` / `ThreadMediaCache` 新增 `previewText`（首帖纯文本摘要，与图片同一次请求解析）。
- `HomeThreadItem` 的 转发 / 收藏 / 积分 / 浏览 改为可选：论坛列表页不输出这些字段时界面隐藏对应数字，**不伪造**。

## 二、需要真机（已登录）复核的点

搜索、发帖、板块菜单解析**依赖登录态**，本地沙箱只能拿到游客提示页，因此以下需在真机确认：
1. 搜索结果页模板结构（兜底解析已覆盖常见形态，必要时按真机 HTML 微调选择器）。
2. 发帖提交后的回显（是否含 `viewthread.php?tid=`；无则走板块列表复查）。
3. 首页媒体 / 摘要检测在真实网络下的耗时（20 条 × 并发 4）。

## 三、下一步候选
- 消息（站内短信 / 系统消息）与私信会话接 `pm.php`。
- 「我的」宫格（帖子 / 回复 / 收藏）接真实页面。
- 收藏 / 站内转发接真实接口。
