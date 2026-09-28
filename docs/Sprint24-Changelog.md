# Sprint 24 · 编辑自己的帖子（B4）

> 一句话：用户又补了两张登录态页面（**帖子浏览页** `viewthread.php?tid=3468587` + **编辑页**
> `post.php?action=edit&fid=2&tid=3468587&pid=74756533&page=1`），据此把「编辑自己的帖子」**完整接线**：
> 本人楼层出现「编辑」入口 → 打开编辑页预填标题/正文 → GBK 提交 → **回读编辑页确认**。
> 同时确认：**该账号权限下站点不提供「删除自己的帖子」**，按红线不伪造。

---

## 一、真实页面实测（两张夹具，GBK 原字节，逐字节一致）

| 夹具 | 来源 | 关键结构 |
|---|---|---|
| `viewthread_tid3468587_pc.html` | `viewthread.php?tid=3468587`（17 楼：1 楼主 + 16 回复） | 楼主（本人 uid=19657）操作栏里有 **`<a class="editpost" href="post.php?action=edit&fid=2&tid=3468587&pid=74756533&page=1">编辑</a>`**；**只有本人楼层有** |
| `post_edit_fid2_tid3468587_pc.html` | `post.php?action=edit&fid=2&tid=3468587&pid=74756533&page=1` | `form#postform`：action=`post.php?action=edit&extra=&editsubmit=yes&mod=`；hidden=`formhash=ec78b12a / fid=2 / tid=3468587 / pid=74756533 / page=1 / posttime / iconid`；`input[name=subject]`（预填「亚运会热度不高啊」）；`textarea[name=message]`（预填原帖）；`button[submit name=editsubmit value=true]` |

**负面结论（删除）**：编辑页与帖子页**都没有**删除控件（无 `name=delete` / `action=delete` / `modthread`；
编辑页唯一的「删除」是工具栏「删除线」）。⇒ 该账号权限下站点**不提供**「删除自己的帖子」，客户端**不显示删除按钮**。

---

## 二、改了什么（7 个文件）

| 文件 | 改动 |
|---|---|
| `Models/Models.swift` | `Post` 增 `var editPath: String? = nil`（站点原样编辑链接；仅本人楼层有；带默认值，老调用点不动） |
| `Parsers/ThreadDetailParser.swift` | PC 解析：在楼层容器内取 `a.editpost[href]` → `editPath`（**只搬运页面已有链接，不自行拼 URL**） |
| `Repositories/EditPostRepository.swift` | 🆕 `ParsedEditForm` + `EditPostRepository`：`loadEditForm` / `parseEditForm` / `submitEdit`（GBK 提交 → **回读编辑页确认**）；请求前过 `isAllowedForumPath` 守卫 |
| `Features/Compose/EditPostView.swift` | 🆕 编辑 Sheet：打开时加载编辑页预填**标题 + 正文**，保存走仓库；加载/保存/失败态齐全 |
| `Features/Thread/PostDetailRow.swift` | 操作栏增「编辑」（铅笔）——**仅 `post.editPath != nil` 时出现**（站点不给入口就不显示，绝不伪造） |
| `Features/Thread/ThreadDetailView.swift` | `editingPost` 状态 + 编辑 Sheet 接线（Demo / 正式两个分支）+ 保存后**按当前页重新加载**（服务器回读为准） |
| `docs/Roadmap.md` | B4 状态更新：编辑已完成；删除站点不提供 |

> 复用现有 `DiscuzFormParser`（`formRegion(requiring:)` + `parse`）：编辑页与发帖页共用 `#postform`，
> **通用解析器无需改动**即可解析（Sprint 23 已钉死）。

---

## 三、验证

```
verify24（cheerio 镜像 ThreadDetailParser 的 editPath 抽取）: 11/0 ✅
  postnum = 17 ✓  a.editpost 仅 1 个 ✓  链接 = post.php?action=edit&fid=2&tid=3468587&pid=74756533&page=1 ✓
  编辑入口在第 1 楼 table 内 ✓  帖子页无删除控件 ✓
verify22（分类 / 附件密钥）: 全部通过 ✅      verify23（编辑表单字段）: 全部通过 ✅

新增单测（alpha-build 的 xcodebuild test 会编译执行）:
  testThreadDetailParser_editLinkOnlyOnOwnPost  —— 17 楼；仅楼主有 editPath，其余为 nil
  testEditPostRepository_parseEditForm          —— action / formhash=ec78b12a / subject / message / tid / pid / editsubmit

静态检查: swiftcheck 0 问题 · swiftlint-lite 通过（106 文件）· dups 175 符号无重名
```

---

## 四、留下的取舍与待办

1. **只编辑标题 + 正文**：站点的 `typeid` 分类是 JS 菜单、页面 `<select>` 为空值，故**不提交 typeid**，
   避免张冠李戴改掉分类（与发帖页的 `typeid` 处理不同：发帖页有真实 select 才带）。
2. **编辑入口只在本人楼层**：完全由站点是否渲染 `a.editpost` 决定 —— 我们既不猜「是不是我的帖子」，
   也不自行拼编辑 URL。
3. **删除不做**：站点不提供入口。若以后你的用户组获得删除权限（页面里出现删除控件），
   再按其真实结构接（不预先发明）。
4. 🔸 **仍需一次 CI 真机/模拟器编译**：本轮改动面较大（2 新文件 + 3 文件接线），
   Windows 本地无 Xcode，**只能靠 `alpha-build` 的 `xcodebuild test` 确认能编译**。
   若 CI 报编译错，优先看第一个 `error:`。
