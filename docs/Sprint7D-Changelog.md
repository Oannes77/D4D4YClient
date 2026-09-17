# Sprint 7D 变更日志

## 交付目标

- 建立统一 Theme Design Token 系统。
- 实现回复 UI 接入（ReplyEditor + ReplyViewModel + ThreadDetailView）。
- 按附件视觉规范对首页、板块列表、帖子列表、帖子详情进行论坛化收敛。

## 新增文件

| 文件 | 说明 |
|------|------|
| `Features/Thread/ReplyEditor.swift` | 帖子底部回复编辑器，登录态显示输入框+发送按钮，游客态显示登录提示 |
| `Features/Thread/ReplyViewModel.swift` | 回复编辑器 ViewModel，封装 `ReplyRepository.submitReply` 调用与状态 |
| `docs/UIDirectionSprint7D.md` | Sprint 7D UI 方向与实现说明 |
| `docs/Sprint7D-Changelog.md` | 本变更日志 |

## 修改文件

| 文件 | 主要改动 |
|------|---------|
| `Shared/Theme/DesignTokens.swift` | 扩展为完整 Theme Token：Primary / Background / Surface / Text / Divider / Border / Success / Warning / Error / Brand Gradient |
| `Shared/AvatarView.swift` | 接入 Discuz 真实头像接口 `uc_server/avatar.php?uid=xxx&size=middle`；失败/无 uid 回退系统中性默认头像 |
| `Shared/ErrorRow.swift` | 使用 Theme Token |
| `Features/Thread/ThreadDetailView.swift` | 接入 `ReplyEditor`；使用 Theme Token；回复成功后跳末页刷新 |
| `Features/Thread/ThreadDetailViewModel.swift` | 新增 `refreshToLastPage()` |
| `Features/Thread/PostCell.swift` | 使用 Theme Token |
| `Features/Thread/PostHeader.swift` | 头像 40px，使用 Theme Token |
| `Features/Thread/PostContent.swift` | 使用 Theme Token |
| `Features/Forum/ThreadListView.swift` | 头像 40px，列表化（无 Card），使用 Theme Token |
| `Features/Home/HomeView.swift` | 取消顶部 Banner，改为「常用板块 / 最近浏览 / 最近帖子 / 最近访问板块」文字列表 |
| `Features/Forums/ForumListView.swift` | 纯文字列表，已固定板块使用线性 `pin` 图标 |
| `Features/Account/LoginView.swift` | 使用 Theme Token |
| `Features/Profile/ProfileView.swift` | 使用 Theme Token |
| `Features/Profile/SettingsView.swift` | 使用 Theme Token |
| `App/D4D4YApp.swift` | Tab bar tint 使用 Theme primary |

## 未改动（红色线）

以下文件在本次 Sprint 中**未修改**，保持 Sprint 7C 状态：

- `Network/HTTPClient.swift`
- `Parsers/*.swift`
- `Repositories/ForumRepository.swift`
- `Repositories/ReplyRepository.swift`
- `Core/Authentication/*.swift`

## 打包信息

- 路径：`E:/workbuddy/2026-09-16-22-09-26/D4D4YClient.zip`
- 大小：**155,706 bytes**
- 总文件：**54**
- Swift 文件：**42**

## 未解决问题

1. 未在真实 Xcode / iOS 设备上编译运行，真机效果待验证。
2. 头像接口路径基于 Discuz 标准假设，若 4D4Y 实际部署不同需微调。
3. `HTMLContentView` 由 HTML 自身决定文字颜色，未与 Theme Token 联动。
4. 字号 / 行距 / 列表密度偏好设置已预留，尚未接入视图。
