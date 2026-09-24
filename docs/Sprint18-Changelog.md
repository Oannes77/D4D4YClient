# Sprint 18 · 整体切到 PC 模板（图片/附件真正可用）

> 一句话：**把客户端的全局 User-Agent 从移动 Safari 换成桌面 Chrome/Edge**，
> 于是站点返回完整 PC 模板 —— 帖子配图、附件图、发帖上传、关注入口全部真实可用。
>
> 触发：用户质问「GitHub 上有人做过这个程序，让你参考，为什么到这个阶段还在讨论 web 还是 PC」。
> 排查后确认：**参考实现（`webrules/4d4y`）从第一天就用桌面 UA**，
> 而我们从立项起用移动 UA，是**没有被讲明的技术选型**，它正是「图片看不到」的根因。

---

## 一、根因（一句话说清）

站点按 User-Agent 分发两套模板：

| UA | 模板 | 后果 |
|---|---|---|
| 移动 Safari（改前） | `templates/wap/` | 正文极少配图；附件图**完全不渲染**；无查看数；发帖页无上传域 |
| 桌面 Chrome（改后） | 完整 PC 模板 | 正文图 + 附件图齐全；有查看数；`form#imgattachform` 提供上传凭据 |

同一帖实测：WAP 125KB / PC 314KB；`<img>` 6 个 / 178 个。

---

## 二、改了什么（解析与网络层 11 个文件 + 新增关注链路）

| 文件 | 改动 |
|---|---|
| `Network/HTTPClient.swift` | `defaultHeaders` 换桌面 Chrome/Edge UA（参考实现同款），补齐 `Referer` / `Upgrade-Insecure-Requests` / `Cache-Control` / `Accept-Language`。删除只用于单次覆盖的 `desktopHeaders` 与 `mobileUserAgent` —— 现在**全站只有一套头**。 |
| `Repositories/ImageMetadataRepository.swift` | 去掉 `desktopHeaders` 覆盖（已无意义），更新注释 |
| `Parsers/ThreadListParser.swift` | **重写**：PC 优先（`tbody[id^=normalthread_]` + `span#thread_<tid>>a` + `td.author cite>a` + `td.nums>strong/em` + `td.lastpost`），WAP 兜底。**新增查看数**。 |
| `Parsers/ThreadDetailParser.swift` | **重写**：PC 优先，以 `a[id^=postnum]` 为**楼层锚点**向上找 `table`（因此屏蔽楼也能列出）。新增 `div#threadtitle h1` 标题解析；把 `div.postattachlist img[file]` 的真实地址以 `<img>` 追加到正文，供图片区提取。WAP 兜底保留。 |
| `Parsers/PaginationParser.swift` | PC 优先（`div.pages > strong` / `a.next` / `a.last`），WAP 兜底；新增 `strippingSessionID` —— PC 链接带 `&sid=…`，我们始终带 Cookie，**不需要它在 URL 里传递**。 |
| `Parsers/ForumMenuParser.swift` | 容器候选由单一 `#silder_l` 扩为 5 个 + **整页扫描兜底**；子版块判定改为沿父链看 `sub`/`child`/`dd`。 |
| `Parsers/ThreadImageParser.swift` | 扫描范围由整页 / `td.t_msgfont` 改为 **`div.postmessage`**（附件图在 `t_msgfont` 之外，只取前者会漏掉全部附件图）；过滤规则**不再要求同域**（老帖图多在外链图床），改为「非噪声 + 非广告域」。 |
| `Parsers/DiscuzFormParser.swift` | 新增 `attachmentUploadKeys(in:)` —— 解析 `form#imgattachform` 的 `uid`/`hash`。 |
| `Repositories/PostRepository.swift` | 附件上传**按 SWFUpload 两步协议重写**（见下）。 |
| `Features/Thread/PostContent.swift` | `extractImageURLs` 改为直接复用 `ThreadImageParser`（单一真相，且优先取 `file` 属性）。 |
| `Models/MySpaceModels.swift` | 🔴 修 bug：`isUserList` 由 `.friends \|\| .follows` 改为只 `.friends` —— **「关注」是主题型**（`my.php?item=attention&action=add&tid=`，参数是 tid），归为用户型会让列表一条都认不出。 |

### 附件上传：从「错的做法」改成正确协议

| | 改前（**错的**） | 改后（参考实现验证过） |
|---|---|---|
| 流程 | 文件与正文塞进**同一个** multipart 请求 | **两步**：① 先传文件换 `aid`；② 再普通 GBK 表单发帖 |
| 第一步 | — | `POST misc.php?action=swfupload&operation=upload&simple=1&type=image\|attach`，字段 `uid` / `hash` / `Filedata`（**原始文件名**）→ 响应 `DISCUZUPLOAD\|0\|<aid>` |
| 第二步 | — | `POST post.php?action=newthread&…`，正文尾追加 `[attachimg]<aid>[/attachimg]`（图片）或 `[attach]<aid>[/attach]`，并带 `attachnew[<aid>][description]=` |
| 失败处理 | — | 任一附件失败**整体中止**，不发「正文与附件不符」的半个帖子 |

---

## 二之二、「关注」接入（本轮顺手补完的欠账）

站点 PC 模板的 `favoritewin` 弹层里，收藏与关注是**并排的两个入口**：

```html
<a onclick="ajaxget('my.php?item=favorites&tid=193033', 'favorite_msg')">[收藏此主题]</a>
<a onclick="ajaxget('my.php?item=attention&action=add&tid=193033', 'favorite_msg')">[关注此主题的新回复]</a>
```

两个地址的参数都是 **tid** ⇒ 4D4Y（Discuz! 7.2）的「关注」关注的是**主题**，不是人。
此前把「关注」归为用户型列表（按 `space.php?uid=` 抽取），会**一条都认不出来**；
`Shared/DemoData.swift` 还让「关注」返回「本站没有这个栏目」，也是错的。
本轮一并修正：

| 文件 | 改动 |
|---|---|
| `Repositories/AttentionRepository.swift` | 🆕 关注数据层：`my.php?item=attention`；add 用站点原样地址，remove 走「列表页自带删除链接优先 + 候选兜底」，**一律回读列表确认**，确认不了返回 `.unconfirmed` |
| `Core/AttentionStore.swift` | 🆕 关注状态单例（与 `FavoritesStore` 同构）；Demo 模式用 `DemoData.attentionDemo()` |
| `Features/Thread/PostDetailRow.swift` | 操作栏加第六个图标：铃铛（`post-attention`），实心 = 已关注 |
| `Features/Thread/ThreadDetailView.swift` | 接 `AttentionStore`，`toggleAttendThread()`（未登录先给登录入口，绝不假装成功） |
| `Models/MySpaceModels.swift` | 修 `isUserList`（只认 `.friends`）；新增 `hasExternalEntry`（关注的入口不在 `my.php` 导航里，不能凭导航缺项判「本站没有」） |
| `Repositories/MySpaceRepository.swift` | `sectionMissing` 判定加上 `hasExternalEntry` 例外 |
| `Features/Profile/MySpaceListView.swift` | 空态文案「你还没有关注任何主题」（原来是「关注的人」） |
| `Shared/DemoData.swift` | 「关注」改为返回**主题型**样例，与真实口径一致 |
| `Core/Authentication/SessionManager.swift` | 登出 / 掉线时清 `FavoritesStore` 与 `AttentionStore` 的内存状态 —— 否则游客会看到上一账号的实心星标 / 铃铛，属于替游客「假装」服务器状态 |

---

## 二之三、把站点事实钉进单元测试（新增 7 条）

新增 PC 夹具（`Tests/Fixtures/*_pc.html`）之后，用 XCTest 把这些**只能在真实页面上验证**的事实固定下来，
以后谁改错了会立刻红：

| 测试 | 钉住的事实 |
|---|---|
| `testThreadListParser_pcTemplate` | 75 条；tid=193033 的标题/作者/分类/回复数/**浏览量 673371**；匿名帖 `authorID == nil` |
| `testPaginationParser_pcTemplate_listPage1` | 第 1 页 / 共 919 页；next = `forumdisplay.php?fid=14&page=2`（**`&sid=` 必须被剥掉**） |
| `testThreadDetailParser_pcTemplate` | 50 楼（含 1 屏蔽楼）；标题去掉 `[分类]` 前缀且分类被提取 |
| `testThreadDetailParser_pcTemplate_attachmentImageAppended` | 附件图（`file` 属性、位于 `t_msgfont` 之外）被追加进楼层正文 |
| `testThreadImageParser_pcTemplate_keepsExternalAndAttachmentImages` | 过滤后保留 6 张 = 4 张外链图床 + 2 张附件图（**不再要求同域**） |
| `testAuthorityURLs_comeFromRealPCTemplate` | 收藏 / 关注的权威地址**真的写在站点 PC 模板里**，且与仓库里的常量一致 |
| `testMySpaceKind_attentionIsTopicTypeNotUserList` | 关注是主题型；`hasExternalEntry == true` |

---

## 三、验证（用真实 PC 页面跑选择器镜像）

夹具换成 PC 版（`Tests/Fixtures/*_pc.html`），用 cheerio（与 SwiftSoup 同为 CSS 选择器引擎）逐条镜像 Swift 里的选择器：

```
列表页  tbody[id^=normalthread_]        = 75 → 解析成功 75/75
        标题/作者/日期/回复/**查看数**/分类/最后回复  全部取到，0 缺失
        分页  当前页=1  next=forumdisplay.php?fid=14&page=2  末页="... 919"
详情页  a[id^=postnum]                  = 50 楼（49 有正文 + 1 屏蔽楼）
        作者/楼层号/时间/pid             缺失 0
        标题  [心得技巧] + 正文标题       分类与标题正确拆分
图片    div.postmessage 内 <img>        = 8
        其中带 file 的附件图              = 2
        过滤后保留                        = 6（4 张外链 + 2 张附件图）
登录页  formhash / questionid / option   ✓（8 个安全提问）
```

> 关键验证结论：**附件图的真实地址只在 `file` 属性上**，`src` 是 `images/common/none.gif` 占位；
> 且它位于 `div.postattachlist`（`td.t_msgfont` **之外**）—— 两处细节都踩过才会 0 张图。

---

## 四、其余解析器：为什么不用改

排查后确认它们**本来就是模板无关**的（这也是本轮改动面小于预期的原因）：

| 解析器 | 为何无需改 |
|---|---|
| `LoginFormParser` | 纯正则取 `input[name=formhash]` / `select[name=questionid]` |
| `SearchResultParser` | 复用 `ThreadListParser`（已 PC 优先）+ 通用 `a[href*=viewthread.php]` 兜底 |
| `ProfileParser` | 全文正则匹配「积分 / 帖子 / 用户组」标签 |
| `PMListParser` / `PMConversationParser` | 按 `pm.php` / `space.php?uid=` 链接抽取 + 时间戳分块启发式 |
| `MySpaceParser` | `my.php` 页内导航动态发现 + 通用锚点抽取 |
| `DiscuzFormParser` | 正则解析任意 `<form>` 的 hidden / textarea / submit |

⇒ **UI 层一行未改**（界面拿的是解析后的模型，与模板无关）。

---

## 五、遗留与待验证

1. 🔸 **真机登录验证**：发帖附件的 `uid`/`hash` 是否真在 `form#imgattachform`、
   SWFUpload 端点是否接受非图片的 `type=attach` —— 游客拿不到发帖页，**只能真机确认**。
   失败时界面会明确报「附件上传失败（帖子未发出）」，不会假装成功。
2. 🔸 **`my.php` / `pm.php` / `search.php` / `space.php`** 在 PC 模板下的真实结构仍无法本地抓取
   （游客一律返回登录门）。这些解析器是**链接 / 正则 / 启发式**驱动的，理论上跨模板可用，
   但需真机确认。
3. 🔸 **老附件已被站方清理**：2004–2005 年的附件图服务器上已 404（如 tid=156304 三十张全失效），
   任何方案都取不回，客户端如实不显示。
4. 侧边抽屉 `#silder_l` 是 WAP 模板的结构；PC 模板下版块菜单走 `div#nav` 或整页扫描兜底，
   实测 `div#nav` 命中。
5. 🔸 **取消关注的地址未经真机验证**：站点只在 PC 模板里给出了「关注」的 `add` 地址，
   没有给 `delete`。所以取消走「关注列表页自带的删除链接优先 + 候选兜底 + **回读关注列表确认**」；
   确认不了会返回 `.unconfirmed` 并如实提示「未能确认取消成功」，不会假装成功。
6. ✅ **本次可本地回归**：`Tests/D4D4YClientTests.swift` 新增 7 条 PC 夹具测试，
   与截图验收同一次 CI 一起跑 —— 编译或解析回归会直接在 CI 里红，不必等看图。

---

## 六、教训

**技术选型不得静默决定。** UA 决定模板，模板决定「用户看不看得见图」——
这属于产品可见行为，不是内部实现细节，立项时就该讲明代价。
本轮之前，这个选择被埋了 7 天，直到它以「图片看不到」的表象暴露出来。

**有现成第三方实现时必须先找来读。** `webrules/4d4y` 一直在，用户也提过，
它能一次回答「UA 怎么选 / 选择器是什么 / 上传协议是什么」——我却摸黑试错了十几轮。

---

## 七、补修：首次 CI 编译失败，以及静态检查的补强

Sprint 18 推上去后，**截图流水线第一轮就跑挂了**（`0` 张 png）——
「本地自检通过」不等于能编译。两个错都不是括号问题：

| # | 位置 | 错误 | 怎么来的 |
|---|------|------|----------|
| 1 | `Parsers/ForumMenuParser.swift:51` | `incorrect argument label … have 'looksLikeSubForum:', expected 'isSubForum:'` | 把 helper 改名成 `looksLikeSubForum` 时，**顺手把调用点的标签也改了** —— 但 `ForumSection` 的属性仍叫 `isSubForum` |
| 2 | `Parsers/ThreadDetailParser.swift:68` | `binary operator '+' cannot be applied to operands of type 'OSLogMessage' and 'String'` | `os.Logger` 的插值会被转成 `OSLogMessage`，**它没有 `+` 运算符**，不能像普通字符串那样跨行拼接 |

顺带清掉了编译日志里的全部可修警告（都是本轮重写的文件带出来的）：
`try?` 套在不抛错的调用上（`parent()` / `tagName()` / `id()`）、多余的 `await`
（`seedMedia` / `enterDemoSession` / `apply` 都不是 async）、`var` 该是 `let`。

### 新增工具：`analysis/swiftlint-lite.mjs`

之所以会漏，是因为本地唯一的自检 `analysis/swiftcheck.mjs` **只查括号平衡** ——
而上面两个错恰恰是「括号完全平衡、但类型/标签不合法」。
在没有 Xcode 的 Windows 上，用「仓库内自洽的静态推断」把这三类补上：

| 规则 | 级别 | 做法 |
|------|------|------|
| `memberwise-label` | **硬错误** | 扫出所有 `struct`（无自定义 init）的属性名集合，再去扫全部 `X(...)` 调用点；**标签不在集合里就报错** —— 专治上面第 1 类 |
| `oslog-concat` | **硬错误** | `Log.xxx.info/warning/…(...)` 参数顶层出现 `+` 即报错 —— 专治上面第 2 类 |
| `memberwise-missing` | 警告 | 必填参数没给（自动放过 `@State`/`@EnvironmentObject` 这类 SwiftUI 注入的属性、以及尾随闭包） |
| `soupsoup-redundant-try` | 警告 | `try? x.parent()` 这类冗余（注意 `try? a.parent()?.text()` 里的 `try?` 是给 `text()` 用的，不能误判） |

```bash
node analysis/swiftlint-lite.mjs D4D4YClient        # 硬错误才算失败
node analysis/swiftlint-lite.mjs D4D4YClient --warn # 连警告一起算失败
node analysis/swiftcheck.mjs D4D4YClient            # 括号平衡（已有的）
```

自查过它「真的能抓到」：故意写回错误样例，两类硬错误都能命中；
同时确认不误报 SwiftUI 的 `@State`/`@EnvironmentObject` 属性。

### 教训（补充到本文档上面那条）

**「自检通过」必须说清自检查了什么。** 只查括号平衡就敢说「静态检查 0 问题」，
等于把编译器的活儿揽了一半还报了个通过 —— 下一轮起，两个脚本都要跑，缺一不可。

**验证要覆盖所有 test target。** 截图 workflow 只编 App target，
单测 target（7 条新断言）根本没被编到 —— 所以本轮又用 cheerio 把单测断言
（列表 75 行 / 详情 50 楼 / 浏览量 673371 / 作者 EC uid=1142 / 分类 心得技巧 / 附件图 / sid 剥离）
逐条对着真实 PC 夹具复验了一遍，确认不是「写了个编不过或必挂的测试」。

---

## 八、18.1：首轮验收图的复核与三处修正

重跑 CI 后出图正常（`D4D4YClient_44_artifacts.zip`，**18 张 = 9 界面 × 亮暗，无黑屏**）。
逐张看过之后，改了三处。

### 8.1 18 张图的实际结论（逐界面）

| 界面 | 看图结论 |
|---|---|
| `home` | ✅ 首图预览真的出来了（threads 卡片形态）；被拉黑作者行显示「-已拉黑-」+ 就地「取消拉黑」 |
| `thread` | ✅ 六键操作栏齐全（回复 / 分享 / 收藏 / 关注 / 举报 / 网页版），标题带分类前缀（⚠️ 第六项「网页版」已于 Sprint 19 取消，见 `Sprint19-Changelog.md` §七） |
| `threadShareMenu` | ✅ 分享菜单展开出「系统分享 / 分享给好友」两项 |
| `userCard` | ✅ 加好友 / 私信 / 搜贴 / 拉黑 四键都在 |
| `newPost` | ✅ 板块 / 标题 / 正文 / 图片 / 附件 齐备 |
| `savedThreads` | ✅ 真实主题两条 + 金色星标 |
| `replyPlaceholder` | ✅ 输入框有了可见边界（不再是「像静态文字」的裸 TextField） |
| `reportChat` | ✅ 收件人 4D4Y、输入框预填举报草稿、发送键在 |
| `myFollows` | ✅ 主题型列表（不再是「本站没有这个栏目」） |

⚠️ 但 **`thread` 用的是纯文字帖（193033），没有任何一张图能证明「详情页看得到图」** ——
这一轮最核心的成果恰恰没有入镜。见 8.3。

### 8.2 删掉列表行里那颗金色 ◇「积分」

首页列表行有一项 `◇ 1,520`（积分）。它是 Sprint 10 为了「补齐一行指标位」加进去的，
取值来自**演示数据**；而 `HomeViewModel` / `SearchViewModel` 在真实模式下**永远传 nil** ——
也就是说这是「只存在于截图里、线上永远不会出现」的数字，
等于让验收图通过一个生产环境根本不存在的布局。这与项目「不伪造」的红线直接冲突。

处理：`HomeThreadItem` 删掉 `shares` / `favorites` / `points` 三个字段（前两个同样从未渲染过），
`PostRow` 去掉 ◇ 那一块，调用点一并清理。
**现在列表行只剩站点真有的东西**：回复数 / 分享入口 / 收藏态 / 附件标识 / 浏览量。

### 8.3 新增 `threadImages`：把「详情页有图」拍进验收图

新抓一份 PC 夹具：**tid=439576**（`[HPC] netbook pro图解全攻略`，34 楼，首帖 5 张附件图，
全部托管在 `img02.4d4y.com`，逐张实测 `200 image/jpeg`，单张约 200KB）。
对比过 tid=332225 —— 它首帖 4 张图都在 2006 年的外链图床 `pic.eawan.com` 上，**现已 404**，
拿它做验收图只会拍出一屏「加载失败」占位，反而说不清是功能坏了还是图床没了。

- 新夹具：`Tests/Fixtures/viewthread_tid439576_page1_pc.html`（+ 演示副本）
- 新截图界面：`ScreenshotScreen.threadImages`（滚到操作栏，图片网格就贴在它上方，必然入镜）
- 新单测：`testThreadDetailParser_pcTemplate_withImageAttachments`（34 楼 / 5 张图 / 全部同域）
  —— 它同时是验收图的「防退化」保险：哪天解析不出图了，CI 先红，而不是拍一张没有图的详情页让人误以为「这帖本来就没图」。

### 8.4 演示夹具全部换成 PC 页面

原先 `Demo/DemoFixtures/` 放的是 **WAP** 页面，而线上跑的是 **PC** 模板 ——
**验收的是一套模板、跑的是另一套**，「截图看着没问题」因此并不能推出线上没问题。
现改为三个 `*_pc.html`：`loadForumDisplayFixture()` 与 `loadViewthreadFixture(tid:)` 都读 PC 页面，
演示与线上同一套选择器。（193033 的 PC 页面首帖实测 0 张图，所以换过去不会凭空多出一堆图。）

顺带确认：`HomeThreadItem.shares/favorites/points` 删除后，
`analysis/swiftlint-lite.mjs` 的成员初始化器标签检查 **0 报错** ——
3 个调用点全都同步改到了。

### 8.5 演示图源换掉 `placehold.co`

Sprint 13 就记过一笔：全屏画廊用外网占位图，「CI 网络一抖就一直转圈」。
本轮把首页首图与画廊的图源都换成**论坛自己的附件图地址**（实测 200 OK）：
既去掉一个外部抖动源，也顺带证明「客户端真的能下载论坛图片」——
这正是 Sprint 18 换模板要解决的问题。

### 8.6 留待用户决定的（没擅自改）

**首页右下角的悬浮发帖按钮会压住列表正文。** 这是 FAB 的固有行为
（内容从它下面滚过去），不算 bug，但在截图里确实盖住了第 2 条的一部分标题。
两个方向：① 保持现状；② 挪到导航栏右上角（与帖子详情页的铅笔一致，彻底不遮挡）。
默认不动 —— 等你圈图时定。

> ✅ **2026-09-24 已定（Sprint 19）**：用户选了第三条路 —— **直接取消 FAB**，
> 在搜索框原位置放一条常驻的 Threads 风格发帖入口（头像 + 「发新帖…」胶囊）。
> 见 `docs/Sprint19-Changelog.md` §四。本节的「①保持现状 / ②挪到右上角」已作废。

### 8.7 本轮验收清单变化

9 界面 / 18 张 → **10 界面 / 20 张**（新增 `threadImages` 亮暗各一张）。

### 8.8 顺带修掉「拿到一堆 UUID 文件名，只能肉眼认图」

`xcrun xcresulttool export attachments` 导出的 png **是 UUID 文件名**，界面名只写在
同目录的 `manifest.json` 里（对应测试里设的 `XCTAttachment.name`，形如 `light-home` /
`dark-threadShareMenu`）。而 `codemagic.yaml` 的 artifacts 只收了 `*.png` —— 于是每次验收
都得把 20 张图逐张点开猜是哪一屏。两处小修：

1. artifacts 补 `screenshots/*.json`（manifest 一起下载，名字↔文件一目了然）；
2. Collect 步骤把映射**直接打进 CI 日志**，连压缩包都不用下。

⚠️ 写这段脚本时踩了个 YAML 坑：`script: |` 的块标量里**不允许出现列 0 的行**，
所以不能用 `python3 - <<'PY' … PY` 这种 heredoc（heredoc 内容必须顶格，而顶格会终止块标量；
缩进又会让 Python 顶层语句报 `IndentationError`）。改为 `python3 -c "…"` 单行，
并在本地用假 manifest 试过正常映射与「字段名变了」的兜底分支。

