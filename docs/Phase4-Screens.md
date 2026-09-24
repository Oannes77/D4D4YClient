# Phase 4：剩余功能与截图验收清单

> 目标：不再「改一点 → 跑一次 CI → 看几张图」的循环。
> 改为「一次列出全部模块 → 一次 CI 出全套图 → 按图统一修改」。

## 一、模块状态

| # | 模块 | 状态 | 说明 |
|---|------|------|------|
| 1 | 登录 / 安全提问 / 退出 | ✅ 已落地（6b24d56） | Discuz 登录、GBK 编码、Keychain、掉线检测 |
| 2 | 首页板块主题流 | ✅ 已落地 | 板块胶囊切换、**默认收起的搜索栏**（下拉才展开）、**常驻发帖入口**、3 行截断、单图 |
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
- 🔴 Sprint 18.1 起，**演示夹具也一律用 PC 模板页面**（`Demo/DemoFixtures/*_pc.html`）。
  理由：演示跑 WAP、线上跑 PC 时，截图「看着没问题」并不等于线上没问题 ——
  验收通道本身就是唯一的验证手段，不能让它验的和跑的不是同一套东西。
- 🔴 演示图源**不用外网占位图**（`placehold.co` 之类）：CI 网络一抖就转圈，
  看过去像「图片功能坏了」（Sprint 13 踩过）。改用论坛自己的附件图地址（实测 200 OK），
  顺带证明客户端真能下载论坛图片。

### UI 硬约定（改界面时不可违反）

| 约定 | 说明 |
|---|---|
| 风格 | Threads 极简风：浅底 + 圆角卡片 + 0.5px 细线 + **扁平无阴影** |
| 色板 | 主色紫 **#534AB7**；深色模式**纯黑 #000** 底 + 紫提亮 **#8F86E8** |
| 卡片 | 一律用 `View.appCard(scheme)` —— 浅色下 background 与 surface 同为 `#FFFFFF`，**不加描边看不见** |
| 输入框 | **必须有可见边界**：`appSurfaceSecondary` 填充 + `appBorder` 0.5pt 描边（范本：`ReplyEditor`）。List 里裸 `TextField` 在浅色下会被当成静态文字 |
| 一级导航 | 固定 3 Tab（首页 / 消息 / 我的）；详情 · 回复框 · 用户卡 · 画廊走 push 或模态，不占 Tab |
| 首页板块条 | **点胶囊 = 进该板块并刷新；在胶囊条上左右滑 = 换板块**（阈值 60pt 且 > 纵向 1.5 倍；选中胶囊自动居中；到头停住不循环） |
| 首页搜索 | **默认收起**（省信息位）；**下拉回弹（内容被拽过顶 y > 4）才展开**，向上滚内容（y < -4）即收起。别改成「常驻显示」或「滚到顶就显示」 |
| 首页发帖入口 | 搜索框下方**常驻一条** Threads 风格入口（当前用户头像 + 「发新帖…」胶囊）。**已取消右下角紫色悬浮按钮（FAB）** —— FAB 固定悬浮必然压住列表正文（Sprint 18.1 验收图里盖住了第 2 条），这条不吃内容位、功能相同 |
| 板块筛选条 | 板块胶囊**下方**一条横向筛选：**主题分类在最前**（首项「全部」，每板块不同），竖线分隔后是排序/时间（时间档在前、热门在后 —— **以页面顺序为准**）。内容与选中态**全部来自板块页自身链接**，客户端不拼参数、不记账；精华/投票/活动**不做**（解析时跳过） |
| 详情附件区 | 楼层底部的**文件型附件**（zip/rar/pdf…）：文件名 + 体积 + 下载次数 + 系统分享。**图片附件不进这里**（`attachimg` 的那批已由图片网格渲染，重复列会让同一张图出现两遍）。只做「分享」不做「假下载」；附件下载在站点侧需要登录，界面如实写明 |
| 详情图片 | 楼层多图**一张一行**、按原始比例铺满宽度（`scaledToFit`，不裁切、不排方块墙）。点击任一张进全屏画廊左右滑 |
| 详情 | 首帖置顶 + 楼层流 + **每页 50 楼 + 页尾分页条**；「眼睛」= 只看该作者（互斥）；长按楼层 = 引用 |
| 回复 / 发帖占位符 | 显示在**输入框外**的斜体小字（不进输入框），提交时与正文**隔一空行**附带；发帖标题留空则自动取正文首行 |
| 操作栏 | 五个真动作（图标 → 功能）：`bubble.right` 回复 / `arrowshape.turn.up.right` 分享（菜单：系统分享 + 分享给好友）/ `star` 收藏 / `bell` 关注 / `exclamationmark.bubble` 举报。**不做点赞**（论坛无原生赞）；**不做「网页版」**（2026-09-24 取消：它当初只为「站内评分」而设，而该站点两套模板都没有评分功能，等于指向一个不存在的能力） |
| 列表星标 | 收藏列表（`SavedThreadsView`）里星标与右侧「›」**同在行的垂直中线**上；别再挂到「详情」那一行的末尾（会低一整行，看着没对齐） |
| 用户卡 | 头像 + 名 + 签名 + 信息框 + 加好友/删好友 + 私信 + 搜贴 + 拉黑（本地）；无 @handle |
| 时间 | 客户端自产时间用 `Shared/RelativeDateText`（今天 09:02 / 昨天 21:04 / 9月18日）；论坛给的 `timeRaw` **原样显示** |
| 列表密度 | 8 / 12 / 18，在 `PostRow` / `PostCell` / `ThreadListView` **同一口径** |
| 列表行数字 | **只显示站点真有的字段**：回复数 / 浏览量（PC 模板才有）。曾经为了「凑满一行」摆过一颗金色 ◇ 积分 —— 那是**演示数据专属、线上永远为 nil** 的数字，等于让验收图通过一个生产环境不存在的布局，已删除（Sprint 18.1）。拿不到就留空，不编 |

### 工程约定

- **纯客户端开关一律放 `Shared/PreferenceStore.swift`**（UserDefaults + ObservableObject 单例：
  `replyPlaceholder` / `showPostContent` / `pushFrequencyMinutes` / `lastPushCheckAt` / `reportAdminUID`），
  **不要再往 SwiftData 加字段** —— 启动早期与后台任务都要读它，且能免迁移。
- 举报收件人已定为 **UID 29 / 4D4Y**，作为 `PreferenceStore` 的内置默认值；
  未登录时只复制链接并提示先登录，**不发私信、不假装发出**。
- `SavedThread` **已弃用**（收藏改服务器），模型定义保留仅为稳定 SwiftData schema，**别删字段**。
- `project.yml` 的 `sources` 是**目录**：新增 Swift 文件免登记；新增测试夹具放进 `Tests/Fixtures/` 即自动成为资源。

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
| 2c | `threadImages` | 🆕 带 5 张附件图的主题（证明**详情页真的能看到图**） | detail-reply（滚到 post-share） | ✅ |
| 2d | `threadImages`（`threadAttachments`） | 🆕 **附件区**（文件型附件：文件名 / 体积 / 下载次数 / 分享）。ⓘ 附件都在靠后楼层（439576 第 3·9 楼、193033 第 11·13 楼），**必须滚到附件行本身**（`post-attachment`）才拍得到 | detail-reply → 滚到 post-attachment | ✅ |
| 3 | `threadReplies` | 帖子回复楼层（滚页尾：50 楼 + 分页条） | detail-page-prev | 全量 |
| 4 | `reply` | 回复框 Sheet | 取消 | 全量 |
| 5 | `userCard` | 用户卡片 Sheet | 加好友 | 全量 |
| 6 | `imageViewer` | 图片全屏预览（图源 = **论坛自己的附件图**，不再用 placehold.co） | — | 全量 |
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

默认只跑**待验收**的 `AppScreenshotTests.targets`（Sprint 20 为 **11 个界面 = 22 张**：home / thread /
threadShareMenu / threadImages / **threadAttachments** / userCard / newPost / savedThreads /
replyPlaceholder / reportChat / myFollows）；需要全量回归时在 Codemagic 设 `SCREENSHOT_FULL=1`，跑满 23 个界面 = 46 张。

## 三、验收方式

1. Codemagic **手动触发** `Screenshots` workflow（默认只跑 `targets`，Sprint 18.1 为 20 张。
   `SCREENSHOT_FULL=1` 时连 `confirmedTargets` 一起跑，23 界面 = 46 张）。
2. 用户一次性浏览，圈出不满意的界面。
3. 我按圈出的界面集中改一轮 → 再跑一次 → 收敛。

不再需要逐张来回跑。已确认的界面移入 `confirmedTargets`，默认不再重复截图。

### 机制（新增界面只改三处）

`Shared/ScreenshotRoute.swift`：枚举加 case + `content` 加分支 + `targets` 加一行。
启动参数 `-DemoScreen=<name>` 直渲目标界面（Tab 类带真 TabBar、push 类包 NavigationStack、
Sheet 类延迟 0.7s 自动弹）。`AppScreenshotTests` 会 `waitForAnchor`（**同时轮询按钮与静态文本**，12s 预算）
后再截图，不用 XCUI 逐级点击。

`Target` 的可选能力：

| 参数 | 用途 |
|---|---|
| `scrollToElement` | 按 accessibilityIdentifier 把元素滚进可视区（**用 `isHittable` 判定**，比固定滑动次数可靠） |
| `tapElement` + `tapWaitText` | 点开 Menu 并等选项出现（用于分享菜单） |
| `name` | 同一界面拍多张时区分文件名 |

### 🔴 三条铁律（都踩过）

1. **锚点必须选在验收点本身或其附近。** 只等一个「页面顶部就有」的元素，会出现
   「等到了 = 假通过，验收点在首屏之外根本没拍到」（Sprint 16：`thread` 锚在导航栏，
   操作栏在长首帖下方，两轮截图都没拍到）。
   **定锚点前先问：验收点会不会落在首屏之外？** 会就配 `scrollToElement`。
2. **Demo 夹具的顺序会影响能否验收。** 首屏只放得下约 1.5 张卡片（第 1 张带大图时更少），
   被测功能所在的那条要排到**第 2 位以内**（Sprint 16：被拉黑作者原本第 3 条，占位看不到）。
3. **ScrollView 锚点必须挂在页尾最后一个元素之后。** 挂在分页条之前会把分页条整个推出屏幕。

### 核对截图

用脚本解码像素判「有没有渲染」，**别只靠肉眼看缩略图**（Sprint 16 曾把浅色图误判成深色）。

🔴 **判据要选对**：用**亮度 1% / 99% 分位差（极差）**，极差 < 12 = 整屏同一颜色 = 界面没渲染出来。
⚠️ **不要用「平均亮度」判黑屏** —— 纯黑深色主题下，一张只有两行条目的「我的收藏」平均亮度只有 2.2，
会**误杀完全正常的截图**（2026-09-24 第一版判据就把 `dark-savedThreads` / `dark-myFollows` 误判成黑屏）；
「左边缘平均亮度 > 110 = 亮色」这类阈值同样会在深色主题上翻车。

**截图夹具不要依赖外网图源。** 收到一批图**先验出身**（文件时间戳 / 有无 `manifest.json` /
界面结构是否与当前代码一致）再逐张看 —— 曾据此认出用户错发的是七天前的旧产物。

### 0 张 / 黑屏的排查

- 0 张 = 编译失败被 `|| true` 吞掉（Collect 步骤会打印 `error:` 摘要）；
  手写 Info.plist 后缺 `CFBundleIdentifier` 时**编译成功但装不上**，同样是 0 张。
- 黑屏 = 截在启动过渡上，靠等元素出现根治。
- **例外**：Collect 打印「The test runner encountered an error」且 error 摘要为**空** =
  runner / 模拟器偶发故障（编译没失败）→ 重跑，或 boot 前 `simctl shutdown all + erase`
  （已写进 `codemagic.yaml` 的 Boot simulator 步骤）。
