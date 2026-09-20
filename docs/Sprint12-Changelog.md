# Sprint 12 变更说明（2026-09-20）

> 主题：**消灭「点了没反应 / 假装成功」的假按钮，并把图片阅读做完整。**
> 本轮所有改动都遵循同一条原则：**做不到的就明确说明，做得到的就真做**，不用本地假状态冒充服务器结果。

## 一、这轮修掉的问题（来自 14 张截图核对）

| 位置 | 问题 | 处理 |
|------|------|------|
| 帖子详情操作栏 | 「转发」「举报」是死按钮；「收藏」只切换本地 `@State`，**假装收藏成功** | 四个图标全部改成真实动作（见下） |
| 楼层正文图片 | 一次只能看一张，不能在本楼多图间左右滑 | 升级为全屏多图画廊 + `n / N` 页码 |
| 私信会话 | 「发送」只弹「尚未接入」 | 接真实 `pm.php` 发送（动态表单 + GBK + 回读确认） |
| 「我的」宫格 | 六个格子全是死按钮 | 收藏 / 黑名单进真实列表；其余进说明页 + 网页版出口 |
| 消息 Tab 角标 | Demo 里写死 `.badge(3)`，与正式版口径不一致 | 与正式版统一：真实未读条数 |
| 楼层屏蔽 | `PostDetailRow` 把 `isBlocked` 硬编码为 `false`，本地黑名单在详情页**不生效** | 改为按 `BlockedUser` 真实计算 |

## 二、操作栏：四个图标，四个真实动作

先说明一个查证结果：**4D4Y 的 Discuz 模板已经把帖子页的「收藏 / 分享」入口整块 HTML 注释掉了**，
真实页面里是这样的：

```html
<!-- <a href="javascript:;" onclick="showDialog($('favoritewin').innerHTML, 'info', '收藏')" class='d2'>收藏</a>
     <a href="javascript:;" id="share" onclick="showDialog($('sharewin').innerHTML, 'info', '分享')" class='d3'>分享</a>
     --><a href="viewthread.php?tid=193033&amp;page=1&amp;authorid=1142" rel='d4'>只看该作者</a>
```

`misc.php?action=favorite` 对游客请求返回空响应，服务端接口无法在客户端验证。
所以「站内转发 / 论坛收藏」这两件事**在当前论坛上做不到**，客户端不装样子，改为功能等价且真实可行的实现：

| 图标 | 动作 | 真实性 |
|------|------|--------|
| 💬 回复 | 弹回复 Sheet（跳页尾 + 引用） | 真实（已验证） |
| ⤴ 分享 | **系统分享面板**，分享该帖网页链接 | 真实（`ShareLink`，系统能力） |
| ⭐ 收藏 | **本地书签**（`SavedThread`，SwiftData 持久化） | 真实（写本机，不伪造服务器成功） |
| 🧭 网页版 | 浏览器打开该帖，站内评分 / 举报在网页端完成 | 真实（论坛原生入口） |

收藏明确标注为**本地收藏**：「我的 → 收藏」里能看到、能滑删、能点回帖子。

## 三、图片：全屏多图画廊

- `PostContent` 现在把「本楼层全部图片 + 被点下标」交给上层；
- `ImageViewer` 新增多图入口 `init(urls:startIndex:)`，用 `TabView(.page)` 左右翻页；
- 顶部显示 `n / N` 页码（`image-viewer-index`），单图时自动隐藏；
- 每张图各自独立缩放 / 平移 / 双击复位，翻页互不影响；未放大时拖拽等于翻页。

## 四、私信发送接真实 `pm.php`

沿用回复 / 发帖同一套原则（**不硬编码任何 POST 参数**）：

1. GET `pm.php?action=view&uid=N`，用 `DiscuzFormParser` **运行时解析**发送表单
   （`action` / 全部 hidden 字段 / `formhash` / textarea 名 / 提交按钮）；
2. 按论坛 charset=gbk 用 GB18030 百分比编码 POST；
3. **回会话页确认正文真的出现**才算成功，否则 `.sendFailed`（明确告知「服务端未确认」）。

界面行为：发送中禁用按钮并显示进度；**只有确认送达才清空输入框**，失败保留内容并弹原因。
演示模式点发送会明确提示「不会真的发送」。

## 五、「我的」宫格不再有死按钮

| 格子 | 去向 |
|------|------|
| 收藏 | `SavedThreadsView`（本地书签列表，可滑删 / 点进帖子） |
| 黑名单 | `BlockedUsersView`（本地屏蔽列表，可一键取消屏蔽） |
| 帖子 / 回复 / 好友 / 关注 | `UnavailableFeatureView`：说明「需要登录后从论坛我的中心读取，客户端尚未接入」+ 按钮「在浏览器中打开论坛网页版」 |

新增两个界面：

- `Features/Profile/SavedThreadsView.swift`（含 `SavedThreadsView` + `BlockedUsersView`）
- `Shared/UnavailableFeatureView.swift`

## 六、其它

- 新增 `SavedThread`（本地收藏模型），已注册进 `ModelContainer`；
- `DemoData.seed` 预置两条本地收藏 + 一条黑名单，截图才有内容；
- 消息 Tab 角标在 Demo 下也与正式版统一口径（真实未读条数，不再写死数字）；
- `ScreenshotRoute` 新增 `savedThreads` / `blockedUsers` 两个演示界面。

## 七、本轮截图清单（默认 6 界面 × 亮暗 = 12 张）

| DemoScreen | 界面 | 等待锚点 |
|------------|------|---------|
| `thread` | 帖子详情（新操作栏） | detail-reply |
| `imageViewer` | 全屏多图画廊（含 `n / N`） | — |
| `chat` | 私信会话（真实发送按钮） | 发送 |
| `profile` | 我的（宫格全部可点） | 主题外观 |
| `savedThreads` | **新增**：我的收藏 | 我的收藏 |
| `blockedUsers` | **新增**：黑名单 | 黑名单 |

## 八、待验证 / 下一步

- `pm.php` 发送表单结构、`my.php` 系列页面结构**都必须登录后才能拿到**，
  本地（沙箱）只能验证游客可达页面，所以本轮仍是**防御式解析 + 明确失败态**。
  你在真机登录后如果看到「结构可能已变化」，把界面提示告诉我即可，我按真实结构修。
- 下一步候选：① 我的帖子 / 回复 / 好友接 `my.php`；② 站内评分（`misc.php?action=viewratings`，游客可见）；③ 消息推送（15/30/60 分钟后台刷新）。
