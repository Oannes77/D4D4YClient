# Sprint 23 · 钉死「编辑自己的帖子」表单（真实编辑页夹具）

> 一句话：用户从浏览器另存了一份**「编辑帖子」页面**（本以为是帖子浏览页），
> 把它变成夹具，确认**编辑表单可被现有通用 `DiscuzFormParser` 解析**；
> 同时查明**删除控件不在编辑页** —— 删除入口必须从帖子浏览页（`viewthread.php`）取得。
>
> 承接 Sprint 22：B 组「编辑/删除自己的帖子」的前置数据收集。

---

## 一、新增真实夹具（`Tests/Fixtures/`，GBK 原字节，逐字节核对一致）

| 夹具 | 来源页面 | 内容 |
|---|---|---|
| `post_edit_fid2_tid3468587_pc.html` | `post.php?action=edit&fid=2&tid=3468587&pid=74756533&page=1`（登录态，作者 uid=19657） | 「编辑帖子」表单 `#postform`，正文预填「好像没以前亚洲雄风热闹了」 |

⚠️ 该页 `saved from url` 表明是 **Discovery(fid=2) 帖 tid=3468587 的首帖编辑页**（不是帖子浏览页）。
按项目「用真实数据」硬规则保留原值（含 `discuz_uid=19657`、`formhash`）。

---

## 二、确认的编辑表单结构（真实页面实测）

```
form#postform  action=https://www.4d4y.com/forum/post.php?action=edit&extra=&editsubmit=yes&mod=
               method=post  enctype=multipart/form-data
  hidden: formhash=ec78b12a  posttime=1790593920  wysiwyg=0
          fid=2  tid=3468587  pid=74756533  page=1  iconid=0
  select[name=typeid]            ← 分类（与发帖页同一套）
  textarea[name=message]         ← 正文（预填原帖内容，可回显）
  button[type=submit name=editsubmit value=true]  文本「编辑帖子」
```

> 结论：**编辑页与发帖页共用 `#postform`**，现有 `DiscuzFormParser`（`formRegion(requiring:)` + `parse`）
> **无需改动即可解析编辑表单**。差异仅在 action 与额外 hidden（`pid`/`page`/`posttime`/`iconid`）。

---

## 三、关键负面结论：删除入口不在编辑页

- 编辑页**没有** `input[name=delete]`、没有 `action=…delete`、没有「删除本帖 / 删除主题」按钮；
  唯一的「删除」二字来自编辑器工具栏的**「删除线」**格式按钮。
- ⇒ 按 Discuz 7.2 惯例，**删除入口在帖子浏览页**（你自己楼层里的编辑/删除菜单）。

---

## 四、改了什么

| 文件 | 改动 |
|---|---|
| `Tests/Fixtures/post_edit_fid2_tid3468587_pc.html` | 🆕 真实编辑页夹具（37755 B） |
| `Tests/D4D4YClientTests.swift` | 🆕 2 条单测（见下） |
| `analysis/verify23.mjs` | 🆕 19 项断言，cheerio/正则镜像 `DiscuzFormParser` |

| 测试 | 钉死的事实 |
|---|---|
| `testDiscuzFormParser_editPostForm` | 真实编辑页可被解析：`action` 含 `post.php?action=edit`；`formhash=ec78b12a`；`fid/tid/pid/page`；`message` 为正文域；提交按钮 `editsubmit=true`；`isMultipart` |
| `testEditPage_hasNoDeleteControl` | 编辑页无 `name=delete`、无「删除本帖」；「删除」仅作「删除线」出现 |

---

## 五、验证

```
verify23（镜像 DiscuzFormParser）   : 19/0 全过 ✅
  postform 定位 ✓  action=post.php?action=edit ✓  formhash/fid/tid/pid/page ✓
  正文预填 ✓  editsubmit=true ✓  multipart ✓  删除控件：无 ✓
静态检查: swiftcheck 0 问题 · swiftlint-lite 通过 · dups 172 符号无重名
```

---

## 六、遗留 / 待用户（B 组下一步）

1. 🔸 **仍缺帖子浏览页**：请另存 `https://www.4d4y.com/forum/viewthread.php?tid=3468587`
   （在已登录浏览器打开该帖后另存）。用它方能：
   - 确认你自己楼层上「编辑」入口的**真实链接**（期望 `post.php?action=edit&fid=..&tid=..&pid=..&page=..`）；
   - 找到**删除入口**（若有）及其地址/表单；
   - 把 `authorID == 会话 uid` 的楼层与编辑/删除按钮接起来。
2. 拿到上述页面后即可实现完整「编辑自己的帖子」（照 `ReplyRepository` 范式：解析表单 → GBK 提交 → **回读确认**），
   删除同理（若站点对普通用户开放删除）。
3. 参考实现 `docs/RefProject.md` **不含**编辑/删除，故删除协议只能从真实页面推导（不盲写端点）。
