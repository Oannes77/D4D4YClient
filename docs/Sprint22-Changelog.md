# Sprint 22 · 用真实登录态夹具钉死「主题分类」与「附件上传密钥」

> 一句话：**用户另存了 4 份已登录浏览器的真实页面**（GBK 字节），把它们变成夹具，
> 把此前「本地无法验证」的两件事钉死 —— Discovery/Buy&Sell 的 `typeid` 分类表、
> 以及发帖页附件上传表单的 `uid`/`hash`。同时发现一个缺口：编辑/删除自己帖子缺 `viewthread` 页面。
>
> 触发：Sprint 18 文档 §五明确「主题分类 / 附件上传密钥只能真机确认（游客拿不到发帖页）」；
> 用户给了试用账号但服务端脚本登录被 Cloudflare 人机挑战拦死（不绕 CF），
> 于是改走用户浏览器另存 HTML 的路，拿到了登录态页面。

---

## 一、新增真实夹具（`Tests/Fixtures/`，GBK 原字节，逐字节核对一致）

| 夹具 | 来源页面 | 内容 |
|---|---|---|
| `forumdisplay_fid2_threadtype_pc.html` | `forumdisplay.php?fid=2`（Discovery，登录态） | `div.threadtype` 内 **15 个** `typeid` 分类链接 |
| `forumdisplay_fid6_threadtype_pc.html` | `forumdisplay.php?fid=6`（Buy & Sell，登录态） | `div.threadtype` 内 **9 个** `typeid` 分类链接 |
| `post_fid14_attachform_pc.html` | `post.php?action=newthread&fid=14`（发帖页，登录态） | `form#imgattachform`：`uid=19657`、`hash=ad05d719…`、`Filedata` 文件域、action 指向 SWFUpload 端点 |
| `search_results_pc.html` | `search.php?searchid=553`（搜索结果页，登录态） | 备用：验证 `SearchResultParser` 的真实登录态结构（本轮未写测试，留待搜索功能回归） |

⚠️ **隐私披露**：这些页面是登录态另存，含 `discuz_uid = 19657` 与会话绑定的 `formhash` / 上传 `hash`。
它们是**论坛公开 UID 与会话令牌**，不是登录密码，且单独无法登录（还需 CF 域下的会话 Cookie，不在文件里）。
按项目「演示夹具必须与线上同模板 / 用真实数据」的硬规则保留原值。若你希望脱敏，可把 `19657` 与两个 hash 改成占位值，
但那样测试就不再是「真实数据钉死」。

---

## 二、改了什么

| 文件 | 改动 |
|---|---|
| `Tests/Fixtures/*.html`（4 个） | 🆕 真实登录态 GBK 夹具（逐字节 = 桌面另存件） |
| `Tests/D4D4YClientTests.swift` | 🆕 3 条单测（见下） |
| `analysis/verify22.mjs` | 🆕 cheerio 镜像两个 Swift 解析器，14 项断言全过（CI 之外本地即可锁死） |

### 单测（会被 `alpha-build` 的 `xcodebuild test` 编译执行）

| 测试 | 钉死的事实 |
|---|---|
| `testBoardFilterParser_categories_Discovery` | `BoardFilterParser.categories` 从 Discovery 真实页解析出 **15 个**分类；`聚会=9 / 汽车=33 / 大杂烩=38 / 投资=57 / 站务=19` |
| `testBoardFilterParser_categories_BuySell` | 从 Buy&Sell 真实页解析出 **9 个**分类；`手机=1 / 掌上电脑=2 / 笔记本电脑=3 / 各类配件=7 / 站务=19` |
| `testAttachmentUploadKeys_fromRealPostPage` | `DiscuzFormParser.attachmentUploadKeys` 从真实发帖页取出 `uid=19657`、`hash=ad05d71943458cb5031a0a0bd738da17` |

> 关键结论：**`BoardFilterParser.categories` 的选择器 `div.threadtype a[href*=filter=type]` 与真实页面完全吻合**，无需改动。
> 之前「本地无法验证分类」的担心，现在用真实数据永久消除（fid=2 / fid=6 都验过）。
> 附件上传两步协议第一步的凭据（`uid`/`hash` + `misc.php?action=swfupload&operation=upload&simple=1&type=image` + `Filedata`）也确认真实存在。

---

## 三、验证

```
verify22（cheerio 镜像）:
  Discovery fid=2  : 15 分类 ✓（聚会/汽车/大杂烩/投资/站务… 全部命中）
  Buy&Sell fid=6   :  9 分类 ✓（手机/掌上电脑/笔记本/各类配件/站务… 全部命中）
  post fid=14      : uid=19657 ✓  hash=ad05d719… ✓  action=SWFUpload端点 ✓  Filedata ✓
  → 全部通过 ✅

静态检查（提交前）:
  swiftcheck.mjs       : 问题文件 0
  swiftlint-lite.mjs   : 通过（无参数标签错误 / OSLog 拼接 / 冗余 try?）
  dups.mjs             : 172 符号无重名
```

---

## 四、遗留 / 待用户

1. 🔸 **编辑 / 删除自己的帖子（B 组）**：本轮**没有** `viewthread.php?tid=` 页面，拿不到
   `editpost.php?action=edit&…` 与删除入口。**需用户在已登录浏览器另存一帖**（`viewthread.php?tid=xxxxx`，
   最好是自己发的帖，这样页面上才有编辑/删除链接），发来后即可新增解析器 + 界面入口。
2. 🔸 `4D4Y.html` 实为**搜索结果页**（`search.php`），不是首页。若要验证首页（`index.php`）结构，
   可另存 `https://www.4d4y.com/forum/` 首页发我（目前不阻塞任何计划功能）。
3. ✅ 附件上传「真机登录验证」缺口已缩小：`uid`/`hash`/`Filedata`/上传端点都已用真实数据确认；
   剩下只差「第二步把 `aid` 拼回 `[attachimg]<aid>[/attachimg]` 发帖」的真机往返，需等能登录的运行环境。

---

## 五、与 Sprint 21 的关系

Sprint 21 识别登录门并给登录出口（已提交 `1dd9fd0`）。本轮是把「登录门之后的页面」用真实夹具固定下来，
二者互补：登录门提示「请登录」→ 登录后这些夹具证明分类 / 附件上传真能解析。
