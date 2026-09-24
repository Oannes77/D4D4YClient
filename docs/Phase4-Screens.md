# Phase 4：剩余功能与截图验收清单

> 目标：不再「改一点 → 跑一次 CI → 看几张图」的循环。
> 改为「一次列出全部模块 → 一次 CI 出全套图 → 按图统一修改」。

## 一、模块状态

| # | 模块 | 状态 | 说明 |
|---|------|------|------|
| 1 | 登录 / 安全提问 / 退出 | ✅ 已落地（6b24d56） | Discuz 登录、GBK 编码、Keychain、掉线检测 |
| 2 | 首页板块主题流 | ✅ 已落地 | 板块胶囊切换、折叠搜索、3 行截断、单图 |
| 3 | 帖子详情 + 50 楼分页 | ✅ 已落地（6e7b316） | 首帖+49 回复，页尾上一页/下一页 |
| 4 | 回复框（多行） | ✅ 已落地（6e7b316） | 占位符在框外斜体，提交时隔行附带 |
| 5 | 用户卡片 | ✅ 已接真实 `space.php`（Sprint 11） | 未登录或结构未识别时只显示已确定信息 |
| 6 | 图片预览 | ✅ 已落地（Sprint 12 / 18） | **多图画廊**：全屏左右滑 + `n / N` 页码 + 单图缩放。Sprint 18 起**附件图也在内**（PC 模板的 `file` 属性） |
| 7 | 搜索结果页 | ✅ 已落地 | 首页搜索栏 → 结果列表（复用信息流卡片） |
| 8 | 发帖页 | ✅ 已落地 | 板块选择 + 标题 + 正文 + 图片附件 |
| 9 | 板块管理 | ✅ 已落地 | 置顶/收藏板块 + 排序（决定首页展示顺序） |
| 10 | 私信会话 + 发送 | ✅ 已接真实 `pm.php`（Sprint 12） | 发送走动态表单解析 + GBK + 回读确认 |
| 11 | 消息（站内短信/系统消息） | ✅ 已接真实 `pm.php`（Sprint 11） | 分段切换 + 真实未读角标 |
| 12 | 我的 / 设置 / 账号安全 | ✅ 全部可点且生效（Sprint 13） | 六行设置：主题 / 占位符 / 显示正文 / 版块管理 / 消息推送 / 账号 |
| 13 | 我的宫格（帖子/回复/收藏/好友/关注/黑名单） | ✅ 六项全部接真实内容（Sprint 14 / 18） | 黑名单＝本地 `BlockedUser`；帖子 / 回复 / 好友 / **关注** / **收藏**＝论坛「我的中心」（`my.php`） |
| 14 | 收藏 / 关注 / 分享 / 举报 | ✅ 已落地（Sprint 16 / 18） | 收藏＝**服务器**收藏；关注＝**服务器**关注主题新回复；分享＝菜单（系统分享 / 站内分享给好友）；举报＝复制链接 + 私信管理员（UID 29） |
| 15 | 我的帖子 / 回复 / 好友 / 关注（`my.php`） | ✅ 已接（Sprint 14） | 先 GET `my.php` **动态发现 item 参数**，再做通用锚点抽取；登录门 / 无此栏目 / 结构未识别分别如实呈现 |
| 16 | 消息推送（后台刷新） | ✅ 已落地（Sprint 13） | 关闭 / 15 / 30 / 60 分钟；真实 BGAppRefreshTask + 真实未读角标 |
| 17 | 站内评分（`misc.php?action=viewratings`） | ❌ 站点不支持 | **两套模板均已复核**：`评分` 计数为 0，确实没有（口径比 Sprint 12 更硬） |

说明：
- Sprint 11 起，**需要登录才有内容**的模块一律走「明确提示 + 登录入口」，不再用内置示例数据冒充真实内容。
- Sprint 12 起，**论坛侧做不到的功能**不装样子：要么用系统能力等价实现，
  要么打开网页版让用户完成，界面不出现死按钮，也不出现「本地假装成功」。
- 🔴 Sprint 18 起，客户端**全局改用桌面 UA**，走站点 PC 模板 —— 图片 / 附件 / 浏览量 /
  发帖上传 / 关注入口由此全部变成真实的。**本文档里所有基于 WAP 模板的判断都要按此重读**，
  凡是写成「站点没有 / 受模板限制做不到」的，先回去查是不是只看到了一半页面。

### 论坛侧能力查证结论（Sprint 12 —— ⚠️ 已被 Sprint 16/18 推翻，见文末）

真实 `viewthread.php` 页面里，「收藏 / 分享」入口被模板**整块注释**：

```html
<!-- <a href="javascript:;" onclick="showDialog($('favoritewin').innerHTML, 'info', '收藏')" class='d2'>收藏</a>
     <a href="javascript:;" id="share" onclick="showDialog($('sharewin').innerHTML, 'info', '分享')" class='d3'>分享</a>
     --><a href="viewthread.php?tid=193033&amp;page=1&amp;authorid=1142" rel='nofollow' class='d4'>只看该作者</a>
```

`misc.php?action=favorite&tid=` 对游客返回空响应 → 服务端收藏接口无法在客户端验证。

> 🔴 **2026-09-24 更正**：上面这段 HTML 是**站点 WAP 模板**（当时客户端用的是移动 UA）。
> 站点按 UA 分发两套模板，**桌面 UA 拿到的 PC 模板里这些入口是活的**，
> 权威地址就写在 `favoritewin` 弹层里：
> `my.php?item=favorites&tid=<tid>`（收藏）、`my.php?item=attention&action=add&tid=<tid>`（关注）。
> 所以「收藏降级成本地书签」这个决定**建立在只看到一半页面的基础上**，Sprint 16 已改回服务器收藏，
> Sprint 18 又把全局 UA 换成桌面 UA 从根上消除歧义。详见 `docs/SiteFacts.md`、`docs/Sprint18-Changelog.md`。

### 我的中心（`my.php`）的查证结论（Sprint 14 —— ⚠️ 「关注」一条已在 Sprint 18 更正）

实测游客访问 `my.php?item=threads` 返回：

```
<p>对不起，您还未登录，无法进行此操作。</p> … <button … name="loginsubmit">登录</button>
```

且 4D4Y 的定制 wap 模板里**没有任何 `my.php` 链接**（帖子页全文搜不到），
所以「我的中心」的列表结构在本地**无法验证**。客户端因此采取：

1. 先 GET `my.php` 本身，从页内导航**动态发现** `item=` 参数与栏目名（不硬编码）；
2. 再做**通用锚点抽取**：帖子型取 `viewthread.php?tid=`（同 tid 取最长文本当标题），
   用户型取 `space.php?uid=`（按 uid 去重）；
3. 四种结果分别如实呈现 —— **有内容 / 真空 / 需要登录 / 本站没有这个栏目**。

> 🔴 **关于「关注」（Sprint 18 更正）**：本文档曾写「Discuz! 7.2 的我的中心没有该栏目」—— **这是错的**。
> 站点 PC 模板的 `favoritewin` 弹层里明写着 `my.php?item=attention&action=add&tid=<tid>`
> （`[关注此主题的新回复]`），**关注真实存在**，而且关注的是**主题**（参数是 tid，不是 uid）。
> 现已接入：「我的 → 关注」为主题型列表（点进帖子详情），详情页操作栏有铃铛可开关，
> 结果一律**以回读关注列表为准**。归错类别（当成用户型）会让列表一条都认不出 ——
> 这就是 `MySpaceKind.isUserList` 只认 `.friends` 的原因。

## 二、一次性截图清单（`-DemoScreen=<name>`，亮 + 暗各一套）

| 序号 | DemoScreen | 界面 | 等待锚点 | 默认跑 |
|------|-----------|------|---------|--------|
| 1 | `home` | 首页（点胶囊进板块 / 滑胶囊条换板块） | home-post-open | 全量 |
| 2 | `thread` | 帖子详情（首帖 + 六键操作栏，含新增的「关注主题」铃铛） | detail-reply（滚到 post-share） | 全量 |
| 2b | `thread`（`threadShareMenu`） | 点开分享菜单：系统分享 / 分享给好友 | detail-reply → 点 post-share | 全量 |
| 3 | `threadReplies` | 帖子回复楼层（滚页尾：50 楼 + 分页条） | detail-page-prev | 全量 |
| 4 | `reply` | 回复框 Sheet | 取消 | 全量 |
| 5 | `userCard` | 用户卡片 Sheet | 加好友 | 全量 |
| 6 | `imageViewer` | 图片全屏预览（Demo 用本地占位图） | — | 全量 |
| 7 | `search` | 搜索结果 | home-post-open | 全量 |
| 8 | `newPost` | 发帖页 | 发布 | 全量 |
| 9 | `boardManage` | 板块管理 | 添加 | 全量 |
| 10 | `chat` | 私信会话 | 发送 | 全量 |
| 11 | `message` | 消息（站内短信/系统消息） | 消息 | 全量 |
| 12 | `profile` | 我的（卡片描边 + 设置框全可点） | 主题外观 | 全量 |
| 13 | `savedThreads` | 我的收藏（中文时间） | 我的收藏 | 全量 |
| 14 | `blockedUsers` | 黑名单（本地屏蔽） | 黑名单 | 全量 |
| 15 | `myThreads` | 🆕 我的中心：我的帖子（`my.php`） | 我的帖子 | ✅ |
| 16 | `myFriends` | 🆕 我的中心：好友（用户型列表） | 好友 | ✅ |
| 17 | `myFollows` | 我的中心：关注（**我关注的主题**，`my.php?item=attention`） | my-space-row | ✅ |
| 18 | `replyPlaceholder` | 🆕 回帖占位符设置 | 效果预览 | ✅ |
| 19 | `pushSettings` | 🆕 消息推送（后台刷新间隔） | 上次检查 | ✅ |
| 20 | `settings` | 阅读设置 | 主题外观 | 全量 |
| 21 | `security` | 账号与安全 | 退出登录 | 全量 |
| 22 | `login` | 登录页 | 登录 | 全量 |

默认只跑**待验收**的 `AppScreenshotTests.targets`（Sprint 18 为 9 个界面 = 18 张：home / thread /
threadShareMenu / userCard / newPost / savedThreads / replyPlaceholder / reportChat / myFollows）；
需要全量回归时在 Codemagic 设 `SCREENSHOT_FULL=1`，跑满 22 个界面 = 44 张。

## 三、验收方式

1. Codemagic 手动触发 `Screenshots`（单次跑完，产出 10 张）。
2. 用户一次性浏览，圈出不满意的界面。
3. 我按圈出的界面集中改一轮 → 再跑一次 → 收敛。

不再需要逐张来回跑。已确认的界面移入 `confirmedTargets`，默认不再重复截图。
