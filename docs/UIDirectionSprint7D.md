# Sprint 7D UI 方向与实现说明

## 1. 视觉基准

附件三张图为最终 UI 视觉参考，但**不把文字/布局直接复制到代码中**。仅提取以下方向：

- **品牌主色**：
  - 浅色：薰衣草紫 / 粉紫渐变，白色文字。
  - 深色：深靛蓝紫，黑蓝背景，白色文字。
- **气质**：安静、高级、克制，长时间阅读舒适。
- **产品定位**：D4D4YClient 是「高级论坛阅读客户端」，不是社交 Feed / 信息流 / 短视频 / 内容推荐 App。
- **UI 原则**：阅读优先、高信息密度、减少装饰、不过度卡片化、不放大面积营销 Banner。

## 2. 论坛化方向调整

基于效果图进一步向论坛化收敛：

| 方向 | 本次实现 |
|------|---------|
| 板块列表 | 纯文字列表，已固定板块使用极简 `pin` 线性图标（低存在感） |
| 帖子列表 | 列表布局，左侧圆形真实头像（40px），标题 + 作者 + 时间 + 回复数 |
| 帖子详情 | 楼层结构清晰：头像、用户信息、时间、楼层编号、正文、图片、底部回复入口 |
| 首页 | 取消顶部 Banner，仅保留「常用板块 / 最近浏览 / 最近帖子 / 最近访问板块」四个文字列表 |
| 头像 | 使用 Discuz `uc_server/avatar.php?uid=xxx&size=middle`；失败或无 uid 回退系统中性头像 |

## 3. Theme Design Token

所有颜色集中在 `Shared/Theme/DesignTokens.swift`，视图通过 `Color.app*` 系列方法按当前 `colorScheme` 取值，**禁止在 View 中散落颜色代码**。

主要 Token：

- `Color.appPrimary(scheme)` / `appPrimaryPressed`
- `Color.appBackground(scheme)` / `appSurface` / `appSurfaceSecondary`
- `Color.appTextPrimary` / `appTextSecondary` / `appTextTertiary`
- `Color.appDivider` / `appBorder`
- `Color.appSuccess` / `appWarning` / `appError`
- `Color.appBrandGradient(scheme)`（用于启动/登录页等未来场景）

## 4. Sprint 7D 新增与改动文件

| 文件 | 说明 |
|------|------|
| `Features/Thread/ReplyEditor.swift` | 新增：帖子底部回复编辑器 |
| `Features/Thread/ReplyViewModel.swift` | 新增：回复编辑器 VM，调用 `ReplyRepository.submitReply` |
| `Features/Thread/ThreadDetailView.swift` | 接入 `ReplyEditor`；使用 Theme Token；回复成功后跳到末页刷新 |
| `Features/Thread/ThreadDetailViewModel.swift` | 新增 `refreshToLastPage()` |
| `Features/Thread/PostCell.swift` | 使用 Theme Token |
| `Features/Thread/PostHeader.swift` | 头像 40px，使用 Theme Token |
| `Features/Thread/PostContent.swift` | 使用 Theme Token |
| `Features/Forum/ThreadListView.swift` | 头像 40px，列表化，使用 Theme Token |
| `Features/Home/HomeView.swift` | 取消 Banner，四个文字列表区，使用 Theme Token |
| `Features/Forums/ForumListView.swift` | 纯文字列表，线性 pin 图标，使用 Theme Token |
| `Features/Account/LoginView.swift` | 使用 Theme Token |
| `Features/Profile/ProfileView.swift` | 使用 Theme Token |
| `Features/Profile/SettingsView.swift` | 使用 Theme Token |
| `Shared/Theme/DesignTokens.swift` | 扩展为完整 Design Token 系统 |
| `Shared/AvatarView.swift` | 接入真实头像接口，失败回退中性默认头像 |
| `Shared/ErrorRow.swift` | 使用 Theme Token |
| `App/D4D4YApp.swift` | Tab bar tint 使用 Theme primary |

## 5. 回复 UI 架构

```
ThreadDetailView
├── ThreadDetailViewModel  → ForumRepository → HTTPClient
└── ReplyEditor (safeAreaInset bottom)
    ├── ReplyViewModel     → ReplyRepository → HTTPClient
    └── 登录状态由 SessionManager 提供
```

- `ReplyEditor` 不直接触碰 Cookie / formhash / POST 参数 / GBK 编码。
- 游客态显示「登录后参与回复」按钮，点击弹出 `LoginView`。
- 登录用户显示输入框 + 紫色发送按钮；输入为空时按钮置灰。
- 提交成功后通过回调触发 `ThreadDetailViewModel.refreshToLastPage()`，跳转到帖子末页查看新楼层。

## 6. 未解决问题

- 未在真实 Xcode / iOS 设备上编译运行，无法验证 SwiftUI 布局与 Theme Token 在真机上的实际效果。
- 头像接口路径基于 Discuz 标准假设（`uc_server/avatar.php`），如 4D4Y 实际路径不同，需调整 `AvatarView.avatarURL`。
- `HTMLContentView` 基于 `NSAttributedString` HTML 导入，其文字颜色由 HTML 决定，未与 Theme Token 联动；后续 Sprint 可替换为完全受控的富文本渲染。
- 字号 / 行距 / 列表密度的用户偏好设置已在 `LocalSettings` 中预留，尚未接入视图。
