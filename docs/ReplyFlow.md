# Sprint 7 Reply 流程验证与动态解析架构

> 目标：登录用户可回复帖子。本文件记录真实抓取结论、ReplyRepository 动态解析架构、未知字段与真机验证方案。
> 原则（用户确认）：iOS 客户端必须依赖真实运行环境请求；不硬编码、不粘贴固定 HTML、不用无头浏览器、不绕过 Cloudflare。

## 0. 验证状态（真实抓取结论）

- 站点：`https://www.4d4y.com/forum/`（Discuz! 7.2，GBK，Cloudflare 前置）
- **登录：✅ 成功**，`cdb_auth` 已正常下发（Python 验证：单 md5 登录成功，详见 §6）。
- **Sprint 7B 回复页抓取：✅ 成功（已获取真实登录态回复表单）**。修正登录哈希（单 MD5）+ 仅用 Cookie 存储自动带 cookie 后，Cloudflare 不再拦截脚本客户端；`my.php` 返回 `discuz_uid = 458246`（真实识别用户），`post.php?action=reply&tid=269563` 返回含 `textarea name="message"` 的真实回复表单（HTTP 200、非游客页、非 CF 页）。**关键证据已齐，可进入 Submit 实现阶段**（但本 Sprint 7B 任务范围只到“验证回复表单”，按要求停止，不写 submitReply / UI）。详见 §0.1。

## 0.1 Sprint 7B 真实回复表单验证（关键证据）

> 抓取方式：镜像修正后的 `LoginRepository`（单 MD5 + 安全问题 qid=7/answer=1116）→ 取 `cdb_auth` → `my.php` 确认 `discuz_uid=458246` → `loadReplyForm` 真实 GET `post.php?action=reply&tid=269563`。请求用 App 同一移动 Safari UA、同一 Cookie 存储，**未绕过 Cloudflare**（本次 CF 未拦截）。

**返回 HTML 关键片段（节选）**：
```html
<script>... discuz_uid = 458246, ... fid = parseInt('14'), tid = parseInt('269563') ...</script>
<form method="post" id="postform"
      action="post.php?action=reply&amp;fid=14&amp;tid=269563&amp;extra=&amp;replysubmit=yes"
      onsubmit="return validate(this)">
  <input type="hidden" name="formhash"  value="1e4a460b" />
  <input type="hidden" name="posttime"  value="1789631818" />
  <input type="hidden" name="wysiwyg"   value="1" />
  <input type="hidden" name="noticeauthor"     value="" />
  <input type="hidden" name="noticetrimstr"    value="" />
  <input type="hidden" name="noticeauthormsg"  value="" />
  <textarea class="postcon" name="message" id="e_textarea" ...></textarea>
  <input type="submit" class="pbtn" value="发新话题">   <!-- 无 name 属性 -->
</form>
```

**ParsedReplyForm 实际结果（字段名全部来自真实页面，无写死）**：

| 字段 | 真实取值 | 来源 |
|------|----------|------|
| `action`（解码后） | `post.php?action=reply&fid=14&tid=269563&extra=&replysubmit=yes` | `<form action>`（含 `&amp;` 需解码） |
| `hidden.formhash` | `1e4a460b` | hidden input |
| `hidden.posttime` | `1789631818`（服务器时间戳，防重放，需即时使用） | hidden input |
| `hidden.wysiwyg` | `1` | hidden input |
| `hidden.noticeauthor` / `noticetrimstr` / `noticeauthormsg` | 空串 | hidden input |
| `message` 文本框 name | `message` | `<textarea name>` |
| `tid` | `269563` | **不在 hidden，而在 action URL 与 JS 全局变量** |
| `fid` | `14` | **不在 hidden，而在 action URL 与 JS 全局变量** |
| `submit` 按钮 | `value="发新话题"`，**无 `name` 属性** | `<input type="submit">` |

**对解析逻辑的修正要求（下一阶段 submitReply 实现时落实，本任务不写代码）**：
1. `tid` / `fid` **不是 hidden 字段**，必须从 `action` URL 解析（或读 JS 全局变量 `tid`/`fid`）。当前 `parseReplyForm` 仅从 hidden 取会得 `nil`，需改为从 action URL query 提取。
2. 提交按钮**无 name**，因此 POST body 无需携带 submit 按钮名/值；`replysubmit=yes` 已随 `action` URL 的 query string 上传（`$_REQUEST['replysubmit']` 即触发）。`submit_name` 留空即可。
3. POST 目标 = 完整 `action` URL（含 `fid`/`tid`/`replysubmit=yes`），body = `formhash`+`posttime`+`wysiwyg`+`notice*`+`message`（urlencoded）。
4. `posttime` 为防重放令牌，必须用刚 loadReplyForm 取到的**新鲜值**，不可复用旧表单。

**对比游客页**：游客访问同一 URL 返回「您还未登录，无权在该版块回帖」+ `discuz_uid=0`、无 `textarea`；登录态返回真实表单。守卫逻辑（游客页→`.notLoggedIn`、CF 页→`.pageUnavailable`）仍然成立且必要。

## 1. ReplyRepository 结构

文件：`Repositories/ReplyRepository.swift`（新建，已纳入 `project.yml` 的 `sources`，自动编译）。

```
ReplyError            // 错误枚举，明确区分失败类型（见下）
ParsedReplyForm       // 动态解析结果模型
ReplyRepository       // 回复数据层
 ├─ loadReplyForm(tid:)      -> Result<String, ReplyError>
 ├─ parseReplyForm(_:)       -> Result<ParsedReplyForm, ReplyError>
 └─ submitReply(tid:message:) -> Result<Void, ReplyError>
```

`ReplyError` 取值：`notLoggedIn`（会话无效）/ `pageUnavailable`（Cloudflare 或拦截页）/ `network` / `parseFailure` / `captchaRequired` / `submitFailed` / `unknown`。
**绝不绕过验证码与 Cloudflare**，二者均返回明确错误。

## 2. 动态解析设计

- **不硬编码任何 Discuz 回复 POST 参数**，全部来自运行时真实页面。
- **loadReplyForm**：`client.request("post.php?action=reply&tid=\(tid)")` → `sendText`。
  - 依赖 `HTTPCookieStorage.shared` 中由 `SessionManager` 注入的登录 Cookie（HTTPClient 默认即使用该存储）。
  - 游客页守卫：HTML 含“您还未登录”/“无权在该版块回帖” → `.notLoggedIn`，**立即中止，不提交**。
  - Cloudflare 页由 `HTTPClient.send` 抛 `.cloudflareChallenge` → 映射为 `.pageUnavailable`，**立即中止**。
- **parseReplyForm**：
  - 选取含回复内容 `textarea`（`name="message"`）的 `<form>`（兜底：含 `post.php` 且有 textarea 的表单）；
  - 提取 `form action`、`所有 <input type="hidden">`（含 `formhash` / `tid` / 其它）、`textarea` 的 name、`submit` 按钮的 `name=value`；
  - 缺 `formhash` → `.parseFailure`（Discuz 防 CSRF 令牌缺失即无法提交）。
- **submitReply**：`load + parse` → 用解析到的 `hidden` 字段 + 回复内容（文本框名动态取）+ 提交按钮名/值，拼装 `application/x-www-form-urlencoded` 体 → POST 到解析到的 `action`。
  - 返回按回显判定：含“发表回复成功/回复成功”→ 成功；含 `seccode`/“验证码” → `.captchaRequired`；含“未登录/无权” → `.notLoggedIn`。

## 3. 当前未知字段列表（Sprint 7B 后更新）

> 以下按 §0.1 真实表单逐项标注状态。**已确认** = 真实页面已抓到；**仍未知** = 需真实 POST 后才能确定。

| # | 字段 | 状态 | 真实取值 / 说明 |
|---|------|------|------------------|
| 1 | 提交地址 `action` | ✅ 已确认 | `post.php?action=reply&fid=14&tid=269563&extra=&replysubmit=yes`（相对路径，含 `&amp;` 需解码） |
| 2 | `hidden` 完整集合 | ✅ 已确认 | `formhash`/`posttime`/`wysiwyg`/`noticeauthor`/`noticetrimstr`/`noticeauthormsg`；**无** `reppost`/`handlekey`/`subject` |
| 3 | `textarea` name | ✅ 已确认 | `message` |
| 4 | `submit` 按钮 name/value | ✅ 已确认 | `value="发新话题"`，**无 name 属性**（触发靠 URL 中 `replysubmit=yes`） |
| 5 | **POST body 编码** | ✅ 已确认（GBK） | **Sprint 7C 实证**：UTF-8 提交中文会存为乱码（楼层照常创建但文字损坏）；GBK 提交中文正确上帖。Swift `submitReply` 用 `.gb_18030_2000` 逐字节 `%XX` 编码 |
| 6 | 成功 / 失败回显文案 | ✅ 已确认（判定方式） | 回显不恒含“发表回复成功”；**以“重新拉帖子末页、含回复文案”为成功判定**（更可靠，不依赖文案） |
| 7 | 验证码 `seccode` | ✅ 已确认（本表单无） | 当前回复表单**不含** `seccode` 字段；若某版块/频次触发，需另行处理（仍不绕过） |
| 8 | `fid` 是否需额外字段 | ✅ 已确认 | `fid=14` 已在 `action` URL 中，body 无需重复；**不在 hidden** |

## 4. 下一步真机验证方案

1. Mac/Xcode 用 `xcodegen` 由 `project.yml` 生成工程并编译，确认 `ReplyRepository` 通过（含现有 19 个 Parser 测试）。
2. ~~先修复 §6 登录 bug~~ —— **已完成**（Sprint 6 修正任务：固定 4D4Y 单 MD5 + `my.php` 二段校验），无需再修。
3. 真机/模拟器登录后，打开帖子 → 调用 `ReplyRepository.loadReplyForm(tid:)` → 打印/查看 `ParsedReplyForm`。**字段已在 §0.1 实测确认**，本环境拿到的真实值与设备端应一致（设备端再做一次确认即可）。
4. **落实 §0.1 解析修正**：`tid`/`fid` 改从 `action` URL 提取（非 hidden）；submit 按钮无 name，body 不含提交按钮名/值；POST 目标用完整 `action` URL。
5. 输入测试回复 → `submitReply`（按 §2 动态拼装，body 用 GBK 编码验证）→ 检查帖子楼层是否真实新增（**不本地伪造**）。
6. 覆盖错误路径：未登录 → `.notLoggedIn`；Cloudflare → `.pageUnavailable`；验证码 → `.captchaRequired`；网络异常 → `.network`。
7. 验证通过后移除 `submitReply` 中的 `TODO(真机验证)` 标注，固化成功标识文案。

## 5. UI 接入（后续阶段，本次未做）

- `Features/Thread/ReplyViewModel.swift`、`ReplyEditor.swift`、`ThreadDetailView` 集成：检查 `AuthenticationState`，`guest` 显示“登录后回复”，`authenticated` 显示纯文本输入框 + `[发送回复]`；回复成功重新请求 `ThreadDetail` 更新楼层。
- 本次仅完成**数据层动态解析架构**；UI 在真机确认提交链路后再接入，避免半成品接线。

## 6. 已知阻塞（重要）

- **Sprint 6 `LoginRepository.pwmd5` 使用【双 md5】，但 4D4Y 实测为【单 md5】**（已修复）。Python 验证：双 md5 登录返回“登录失败”，单 md5 登录成功、`cdb_auth` 下发。
- **修复状态（Sprint 6 修正任务）**：已按用户决定**固定为 4D4Y 单 MD5**（不做运行时算法探测），仅修改 `LoginRepository.pwmd5` 为 `md5Hex(raw)`；并新增 `my.php` 二段校验（未显示“未登录”且能解析出 uid/用户名才视为登录生效）。未触碰 `LoginView`/`SessionManager`/`KeychainStore`/`AuthenticationState`/`HTTPClient`/`Parser`/`ForumRepository`/`ReplyRepository`。
- 该阻塞已解除，可继续推进 Sprint 7 真机回复验证。

## 7. Sprint 7C `submitReply` 实现与真实验证（关键里程碑）

> 本阶段实现真实回复提交，并用真实账号完成端到端验证（登录→GET 回复表单→解析→POST→重拉帖子确认新增楼层）。

### 7.1 submitReply 实现要点（Repositories/ReplyRepository.swift）

- 流程严格 `loadReplyForm → parseReplyForm → submit`，**不跳过动态解析**。
- POST 体：解析到的**全部 hidden 字段** + `message`（textarea name 动态取）；本表单 submit 无 name → **不添加提交按钮字段**。
- `action` 解码 `&amp;`→`&`，**tid/fid 来自 action URL**，不硬编码。
- 编码：GBK（`gb_18030_2000` 逐字节 `%XX`），非 UTF-8。
- 成功判定：POST 后**重新请求 `viewthread.php?tid=N&page=9999`（末页）**，含回复文案即成功；不依赖返回文案、不本地伪造。
- 错误分类：`notLoggedIn`（游客/未登录回显）、`captchaRequired`（seccode/验证码）、`submitFailed`（未出现楼层）、`pageUnavailable`（CF）、`network`。
- **未修改 `HTTPClient`/`Parser`/`ForumRepository`**；POST 复用 `HTTPRequest(method:.post,...)` + `client.send/sendText`，Cookie 走 `HTTPCookieStorage.shared`。

### 7.2 真实验证结果（真实账号 tzdrl，fid=14 / tid=269563）

- **UTF-8 编码**：POST 返回 302 跳 `viewthread.php?tid=269563&pid=74727892&page=21`（楼层已创建），但中文文案在 GBK 论坛存为**乱码** → 编码错误，弃用。
- **GBK 编码**：POST 返回 302 跳 `viewthread.php?tid=269563&pid=74727907&page=21`，重拉末页后 `Sprint7C GBK 正确编码验证 OK 中文测试 7788` **正确出现** → ✅ 提交链路成功。
- 结论：**GBK 为正确编码**；UTF-8 仅对纯 ASCII 安全，含中文必乱码。Swift 实现已采用 GBK。
- 注意：验证产生的 UTF-8 乱码测试帖（pid=74727892）为一次性测试产物，可在论坛后台删除；GBK 帖（pid=74727907）为正确样本。

### 7.3 实际 POST 字段（全部来自 ParsedReplyForm，无猜测字段）

```
formhash=1e4a460b
posttime=1789633072          # 服务器时间戳，防重放，必须即时使用
wysiwyg=1
noticeauthor=
noticetrimstr=
noticeauthormsg=
message=<用户输入>
# 不含 submit 按钮名/值（本表单 submit 无 name）
# fid/tid 已在 action URL：post.php?action=reply&fid=14&tid=269563&extra=&replysubmit=yes
```

### 7.4 未解决问题（本任务范围外）

1. **仍未编译**（Windows 无 Xcode）：GBK 编码（`.gb_18030_2000`）、`URL(string:relativeTo:)` 解析、`HTTPRequest` POST 复用等均需在 Mac/Xcode 真机最终确认。
2. **验证码**：当前 fid=14 回复表单无 `seccode`；若某版块/频次触发，`.captchaRequired` 已就绪但仍无输入 UI（属后续）。
3. **刷新策略**：`verifyPosted` 拉末页确认；UI 层刷新 `ThreadDetail` 的具体时机/分页定位留待 UI 阶段设计。
4. **回复间隔**：Discuz 有“两次回复间隔”限制（实测约 20s+），连续提交过快会被拦；App 端可提示用户稍候。

