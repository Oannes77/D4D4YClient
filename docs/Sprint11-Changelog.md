# Sprint 11 — 消息模块接真实 pm.php · 用户卡去伪造数据 · 分页条裁切修复

> 起点：用户回传 12 张截图（默认 7 项中的 6 项 × 亮暗），逐张核对后修缺陷并推进下一个模块。

## 1. 截图核对结论

| 界面 | 亮 | 暗 | 结论 |
|------|----|----|------|
| `thread`（详情首帖） | ✅ | ✅ | 正常 |
| `threadReplies`（50 楼 + 分页条） | ✅ | ✅ | 50 楼完整；**分页条被屏幕底部裁掉半个 ⇒ 本轮修复** |
| `reply`（回复框） | ✅ | ✅ | 多行大输入框 + 框外斜体占位说明，符合要求 |
| `userCard`（用户卡） | ✅ | ✅ | 底部小弹窗高度合适（数据本轮改为真实来源） |
| `newPost`（发帖） | ✅ | ✅ | 正文框够大，占位说明在框外 |
| `chat`（私信） | ✅ | ✅ | 输入框无占位符，气泡分侧正确 |

另核对：楼层 #50 尾部多出的一行「同意 我也一样」**不是解析越界** ——
夹具 HTML 里它确实属于 50 楼正文（`<div class="replycon">多谢老大…<br /><br />同意 我也一样</div>`），
论坛原帖就这样，保持原样不动。

## 2. 修了什么

### 2.1 详情页分页条被裁切（截图可见缺陷）

`ThreadDetailView` 里「跳到最后回复」用的是 `proxy.scrollTo("lastReply", anchor: .bottom)`，
而锚点 `Color.clear.id("lastReply")` 挂在**楼层流末尾、分页条之前**。
把零高度的锚点对齐到屏幕底部，等于把分页条整个推到屏幕外 —— 截图里只露出上半截。

修法：把锚点移到分页条**之后**，跳转/截图时整条分页条自然进入可视区。

### 2.2 用户卡不再使用编造数据（`Shared/UserCardSheet.swift` 重写）

旧版 `UserCardSheet` 对任何 uid 都从内置 `DemoUsers` 取资料，
连「328 帖 / 9520 积分」这类具体数字都是写死的 —— 直接违反项目「不伪造数字」的红线。

现在：
- 新增 `Parsers/ProfileParser.swift` + `Repositories/ProfileRepository.swift`，资料来自真实 `space.php?uid=NNN`；
- **未登录** → 卡片只显示已确定的用户名 + 提示「登录后查看 UID / 分组 / 帖数 / 积分」+ 登录入口；
- **结构未识别** → 明确说「资料页结构已变化」，不显示任何统计数字；
- 取到的字段才显示（信息框按字段数自适应，不占固定 4 格）；
- 功能键「私信」已接通会话页；加好友 / 搜贴 / 拉黑仍未接（下一轮）。
- Demo / 截图模式保留样例值（`DemoData.userProfileDemo`），截图外观不变。

### 2.3 消息 Tab 接真实 `pm.php`（本轮主线）

新增：

| 文件 | 职责 |
|------|------|
| `Models/AccountModels.swift` | `PrivateMessage` / `PMBubble` / `PMConversation` / `UserProfile`（未知字段一律可空） |
| `Parsers/PMListParser.swift` | 登录门判定 + 通用锚点抽取 `pm.php` 列表 |
| `Parsers/PMConversationParser.swift` | 「含时间戳的最小块 = 一条消息」启发式，解析往来会话 |
| `Parsers/ProfileParser.swift` | 「标签→数值」宽松抽取会员资料 |
| `Repositories/PMRepository.swift` | 收件箱 / 系统消息 / 会话；错误归一为 `PMError` |
| `Repositories/ProfileRepository.swift` | 会员资料；错误归一为 `ProfileError` |
| `Features/Message/MessageViewModel.swift` | 列表状态机 + `UnreadBadge`（真实未读数） |

改动：
- `MessageView` / `MessageChatView` 全部改为网络驱动，含 loading / 空 / 未登录 / 失败四态；
  每种失败态都有「登录」或「重试」出口。
- 消息 Tab 角标由 `RootView` 写死的 `.badge(3)` 改为订阅真实未读数（读不到就是 0，不显示角标）。
- 私信输入框「发送」明确提示「发送接口尚未接入」，**不清空输入框假装发送成功**。
- 系统消息（无会话对象）列表只读展示，不跳进一个空会话。

### 2.4 其它

- 私信样例首条气泡去掉冗余的「老橡树：」前缀（1:1 会话里左侧气泡已经表明是谁）。
- 截图清单把 `message` 从「已验收」移回「待验收」（本轮改动大，需要重新看两眼）；
  默认仍只跑 7 个界面 × 亮暗 = **14 张/次**。

## 3. 诚实性说明（重要）

`pm.php` / `space.php` 都**必须登录**才可达。沙箱实测：
- `search.php`（游客）→「您还未登录，无法进行此操作」
- `space.php?uid=1142`（游客）→ HTTP 200，但正文是「…无法进行此操作」+ 登录表单

所以本轮新增的两个解析器**无法在本地用真实登录态验证**，采用了防御式实现：
先判登录门 → 再按通用结构抽取 → 抽不到就明确报「结构未识别」，绝不返回空列表冒充「没有消息」。
登录后如果结构对不上，界面会明确说「结构可能已变化」，届时按真实页面调整选择器即可。

## 4. 下一步

1. 私信发送（`pm.php?action=send`）、加好友、拉黑 —— 三处已就位的按钮补上真实行为；
2. 「我的」宫格（帖子 / 回复 / 收藏）接 `my.php`；
3. 收藏 / 站内转发 / 举报接接口；
4. 帖子详情正文内嵌图片 + 多图画廊（`viewthread` 游客可访问，可本地验证）。
