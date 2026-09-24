# 4D4Y 站点实测事实（模板分发 / 接口 / 可达性）

> 更新于 2026-09-20。本文只写**实测过**的事实，每条都能用文末的命令复现。
> 目的：避免再出现「同一件事两轮得出相反结论」——2026-09-20 查明，根因是**站点按 UA 分发两套模板**。

---

## 一、站点按 User-Agent 分发两套模板（最关键的一条）

站点对**同一个 URL**返回哪套 HTML，取决于请求的 `User-Agent`：

| 请求 UA | 拿到的模板 | 说明 |
|---|---|---|
| 移动 UA（iPhone Safari 等） | `templates/wap/` | **精简版**，客户端走的就是这套 |
| 其它（桌面 UA、`CFNetwork` 裸 UA、curl/node 默认） | `templates/default/` | **完整 PC 模板**，功能入口齐全 |

⚠️ **客户端 `HTTPClient.defaultHeaders` 里写的就是移动 Safari UA**（`Network/HTTPClient.swift`），
所以 App 全程解析的是 **WAP 模板**；`Tests/Fixtures/` 与 `Demo/DemoFixtures/` 里保存的夹具
（`forumdisplay_fid14_page1.html`、`viewthread_tid193033_page1.html`）同样是 WAP 模板（含 `templates/wap/` 引用）。

⇒ **改 UA 等于换掉所有页面结构**，会连带影响全部解析器与夹具，不能单独改。

### 实测：同一帖两套模板的差异（`viewthread.php?tid=193033`）

| 指标 | WAP 模板 | PC 模板 |
|---|---|---|
| 体积 | 125,591 字节 | 314,129 字节 |
| `<img>` 标签 | **6**（全是主题图标 / 表情） | **178** |
| `attachment.php` / `aid=` | **0** | 2 |
| `postmessage_`（帖子正文容器 id） | **0** | 49 |
| `favorites`（收藏入口） | **0** | 1（`favoritewin` 弹层，活的） |
| `my.php` 链接 | **0** | 有 |

**推论**：WAP 模板是「能读」的最低配 —— 正文可读，但**附件（含以附件形式发布的图片）在 WAP 视图里根本不出现**。
若某天要做「附件/图片完整浏览」，必须先解决模板选择问题（改 UA 或找参数），届时是**整轮重构级**的工作量。

### 实测：无法用参数切换
- `viewthread.php?tid=193033&mobile=no` → 仍是 WAP（125,591 字节）
- 形态不正确的 `?mobile=no` 直接 404
⇒ 目前**只发现 UA 一个开关**。

---

## 二、帖子页的收藏 / 分享 / 关注入口（PC 模板原文）

PC 模板把入口放在**隐藏弹层**（`style="display: none"`，点按钮才 `showDialog` 展开），原文如下：

```html
<div id="favoritewin" style="display: none">
  <h5>
    <a href="javascript:;" onclick="ajaxget('my.php?item=favorites&tid=193033', 'favorite_msg');return false;" class="lightlink">[收藏此主题]</a>&nbsp;
    <a href="javascript:;" onclick="ajaxget('my.php?item=attention&action=add&tid=193033', 'favorite_msg');return false;" class="lightlink">[关注此主题的新回复]</a>
  </h5>
  <span id="favorite_msg"></span>
</div>
<div id="sharewin" style="display: none">
  <h5>
    <a onclick="setCopy('标题\nhttps://www.4d4y.com/forum/viewthread.php?tid=193033', '帖子地址已经复制到剪贴板…')">[通过 QQ、MSN 分享给朋友]</a>
  </h5>
</div>
```

由此确定的**权威接口**：

| 动作 | 地址 | 备注 |
|---|---|---|
| 加入收藏 | `my.php?item=favorites&tid=<tid>` | 站点原样地址，**不带 formhash**；客户端首选候选 |
| 收藏列表 | `my.php?item=favorites&type=thread` | 回读确认用 |
| **关注主题** | `my.php?item=attention&action=add&tid=<tid>` | **「关注」在站点上是存在的**（针对主题的新回复） |
| 站点自己的分享 | 复制「标题 + 链接」到剪贴板 | 站内没有分享给好友的入口；客户端另加了「分享给好友（私信）」，是超集 |
| 评分 | — | **两套模板都没有**（`评分` 计数 0） |
| 原生举报 | — | **两套模板都没有**（`举报`/`报告` 计数 0） |

---

## 三、WAP 模板的收藏 / 分享按钮「确实被注释掉了」

WAP 模板的帖子页（客户端实际拿到的那份）原文：

```html
<div class="w detailbtn bordertop">
  <!-- <a href="javascript:;" onclick="showDialog($('favoritewin').innerHTML, 'info', '收藏')" class='d2'>收藏</a>
       <a href="javascript:;" id="share" onclick="showDialog($('sharewin').innerHTML, 'info', '分享')" class='d3'>分享</a> -->
```

🟢 **这解释了历史结论冲突**：Sprint 12 观察到「入口被模板整块注释」是**对的**（那一套就是 WAP 模板，注释里还有一句提示），
Sprint 16 由用户给出链接后判「功能是真实存在的」也是**对的**（PC 模板里入口是活的、接口真实）。
**两个结论并不矛盾，只是看的不是同一套模板。** 项目里「入口被注释 ≠ 功能不存在」这条经验依然成立：
本客户端因为拿不到 PC 模板，只能改为**直接用已知接口 + 回读确认**，而不是依赖页面里的入口。

---

## 四、游客可达性（两套模板一致）

| 页面 | 游客 |
|---|---|
| `forumdisplay.php`（公开板块，如 fid=14） | ✅ 可读 |
| `viewthread.php` | ✅ 可读 |
| `logging.php?action=login` | ✅ 登录表单 |
| `forumdisplay.php?fid=2`（Discovery） | 🚫 登录门 |
| `post.php` / `pm.php` / `my.php` / `space.php` / `search.php` | 🚫 登录门（HTTP 200，正文是「对不起，您还未登录，无法进行此操作。」+ 登录表单） |

**登录门的安全性**：`HTTPClient.sendText` 统一检测正文里的「您还未登录」→ 发出掉线通知。
WAP 登录门的文案就是「对不起，**您还未登录**，无法进行此操作。」，能被这条规则命中。
（另注：登录门页面自己带一个 `logging.php?action=login` 的 `<form>` 和 `formhash`，
所以**任何「解析页面表单再提交」的流程都必须先确认不是登录门**，否则会把正文提交到登录脚本上。）

---

## 五、复现命令（本地免登录）

```bash
node analysis/uatest.mjs        # 对比 mobile / desktop / 裸 UA 各拿到哪套模板
node analysis/tpldiff.mjs "viewthread.php?tid=193033"   # 两套模板的关键词计数差
node analysis/probe.mjs "pm.php?action=view&uid=29"     # 游客可达性（结果会存到 _probe/）
node analysis/decode.mjs _probe/pm_wap.html             # GBK 页面解码 + 打印表单原文
```

⚠️ `analysis/probe.mjs` 刻意使用**与 App 相同的移动 UA**，所以它看到的结构就是 App 看到的结构
（既有诊断脚本、`docs/` 下的历史探查记录都基于这个口径）。

---

## 六、结论：模板问题对现有功能的影响

| 功能 | 现状 | 是否受模板影响 |
|---|---|---|
| 读帖正文 / 楼层 / 回复 / 发帖 / 收藏 / 好友 / 私信 | 已实现 | 不受影响（WAP 有对应页面，客户端不依赖 PC 入口） |
| 附件上传 | 已实现，待真机验证 | ⚠️ WAP 发帖页的 file 域名未知（游客看不到发帖页）；不排除 WAP 版没有上传域 |
| 浏览帖子内嵌图片 | 用 PC 模板才完整 | ⚠️ WAP 模板图片极少；以附件形式发布的图**看不到** |
| 「关注」 | 目前走 `.sectionMissing`（当作站点无此栏目） | 🔸 **需修正**：`my.php?item=attention` 真实存在，待接入 |
