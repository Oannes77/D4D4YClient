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

**推论**：WAP 模板是「能读」的最低配 —— 正文可读，但**附件（含以附件形式发布的图片）在 WAP 视图里不出现**。

### ⚠️ 但「不出现」的原因是懒加载空转，不是没有数据（2026-09-24 查明）

WAP 帖子页尾部确实为每个楼层输出了附件加载调用：

```html
<script type="text/javascript" reload="1">
  aimgcount[1456951] = [136655];
  attachimgshow(1456951);
</script>
```

`attachimgshow(pid)`（定义在 `templates/wap/js/app.js`）做的是：

```js
obj = $('#aimg_' + aimgs[i])[0];
if(!obj) { aimgcomplete++; continue; }          // ← WAP 页永远走这一支
if(!obj.status) { obj.status = 1; obj.src = obj.getAttribute('file'); }
```

而 **WAP 页里 `id="aimg_"` 与 `file=` 的出现次数都是 0**（实测 tid=156304：
`attachimg` 30 次、`<img>` 16 个、`aimg_` **0** 个）—— 它要找的元素根本不存在，**纯空转**。
真实地址只在 PC 模板里：

```html
<img src="https://img02.4d4y.com/forum/images/common/none.gif"
     file="https://img02.4d4y.com/forum/attachments/day_040117/xxx.jpg"
     thumbImg="1" id="aimg_136655">
```

**关键**：该 `file` 地址**游客可直接下载**（实测 200 `image/png` / `image/jpeg`，
不需登录、不需 Referer、无需 Cookie）。所以附件图**不是拿不到，只是地址只在 PC 模板里**。

### 首图可用率实测（20 个主题，analysis/imgrate.mjs）

| 口径 | 结果 |
|---|---|
| 现状（元数据走 WAP）能解析出首图 | **4 / 20 = 20%**（都是较新、以 `<img>` 内嵌贴图的主题） |
| 改用桌面 UA 抓元数据后可解析出首图 | **10 / 20 = 50%** |
| 其中首图真的能下载（未被服务器清理） | **8 / 20 = 40%** |

⇒ 正确的说法是「**覆盖面不足**」，而不是「图片几乎不存在」。此前据单个帖子下的
「WAP 正文配图极少」属**过度概括**，已更正。

### 老附件会被服务器清理（站点数据现状，任何方案都取不回）

实测 tid=156304（2004 年附件，`day_040117` 等）30 个地址全部 **404**；
而 tid=332225（2006 年 `day_061102`）游客可正常取到。⇒ 年代久远的附件已被站方清除，
客户端**如实不显示**即可，不必也无法补救。

### 实测：无法用参数切换
- `viewthread.php?tid=193033&mobile=no` → 仍是 WAP（125,591 字节）
- 形态不正确的 `?mobile=no` 直接 404
⇒ 模板切换**只有 UA 一个开关**，且**只应逐请求使用**（见下）。

### 取用方式（已落地）

**不要改全局 UA** —— 全部解析器与 `Tests/Fixtures` 都建立在 WAP 模板之上。
正确做法是**逐请求覆盖**：`HTTPClient.request(path:headers:)` 传入 `HTTPClient.desktopHeaders`。
目前全站只有一处这么用：`ImageMetadataRepository.detect`（只为拿附件图地址）。
连带必修：`ThreadImageParser.parsePreviewText` 必须同时认 PC 容器
（`td.t_msgfont` / `[id^=postmessage_]`），否则元数据改走 PC 后首页首帖摘要会变空。

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
| **列表首图预览** | ✅ **已修（07ed852）** | 元数据检测逐请求改用 PC 模板拿附件图地址；实测可用率 20% → 40%（真实可下载） |
| 附件上传 | 已实现，待真机验证 | ⚠️ WAP 发帖页的 file 域名未知（游客看不到发帖页）；不排除 WAP 版没有上传域 |
| **详情页内嵌图片** | 🔸 **待修** | 详情正文仍来自 WAP 楼层 HTML，附件型主题**点进去看不到图** → 与列表首图不一致。修法：详情侧补一次 PC 请求，并需决定呈现位置（正文内 / 顶部图片区） |
| 「关注」 | 目前走 `.sectionMissing`（当作站点无此栏目） | 🔸 **需修正**：`my.php?item=attention` 真实存在，待接入 |
