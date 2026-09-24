# 4D4Y 站点实测事实（模板分发 / 接口 / 可达性）

> 更新于 **2026-09-24（Sprint 18 之后）**。本文只写**实测过**的事实，每条都能用文末的命令复现。
> 目的：避免再出现「同一件事两轮得出相反结论」——2026-09-20 查明，根因是**站点按 UA 分发两套模板**。
>
> 🟢 **2026-09-24 现状**：客户端**已全局改用桌面 UA**（`Network/HTTPClient.swift`），
> 所以 App 现在解析的是 **PC 模板**，图片 / 附件 / 浏览量 / 上传表单全部可用。
> 本文中「WAP 模板」相关段落仍保留 —— 它们是**历史夹具与诊断脚本的口径**，
> 也是解释「为什么早期结论互相矛盾」的关键证据，不要删。
> 变更细节见 `docs/Sprint18-Changelog.md`；权威参照见 `docs/RefProject.md`。

---

## 一、站点按 User-Agent 分发两套模板（最关键的一条）

站点对**同一个 URL**返回哪套 HTML，取决于请求的 `User-Agent`：

| 请求 UA | 拿到的模板 | 说明 |
|---|---|---|
| 移动 UA（iPhone Safari 等） | `templates/wap/` | **精简版**：正文极少配图、附件图完全不渲染、无浏览量、发帖页无上传域 |
| 桌面 UA（Chrome/Edge/Safari 桌面） | `templates/default/` | **完整 PC 模板**，图片 / 附件 / 上传 / 浏览量齐全 |

🔴 **客户端当前用的是桌面 UA**（Sprint 18 起，`Network/HTTPClient.swift` 的 `defaultHeaders`），
与参考实现 `webrules/4d4y` 一致 —— 所以 App 现在走 PC 模板。

⚠️ 但 `Tests/Fixtures/` 里同时留着两套夹具，且**工具脚本 `analysis/probe.mjs` 刻意用移动 UA**：
- `*_pc.html` = PC 模板（当前线上口径，Sprint 18 抓取）
- `forumdisplay_fid14_page1.html` / `viewthread_tid193033_page1.html` = WAP 模板（历史口径）

⇒ **改 UA 等于换掉所有页面结构**，会连带影响全部解析器与夹具。因此 Sprint 18 的做法是
「解析器 PC 优先 + WAP 兜底」双轨，两边都不能拆。

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

### 取用方式（Sprint 18 起：**全局**桌面 UA）

**改前**：全局移动 UA，只让 `ImageMetadataRepository.detect` 逐请求覆盖桌面头。
**改后**：`HTTPClient.defaultHeaders` 直接就是桌面 Chrome/Edge UA + `Referer` +
`Accept-Language` + `Upgrade-Insecure-Requests` + `Cache-Control`，全站只有一套头。
随之而来的连带调整（都已落地）：

| 连带项 | 为什么必须一起改 |
|---|---|
| `ThreadListParser` / `ThreadDetailParser` / `PaginationParser` / `ForumMenuParser` | PC 结构完全不同，改为 **PC 优先 + WAP 兜底** |
| `ThreadImageParser.firstPostSection` | 扫描范围要认 `div.postmessage`（附件图在 `td.t_msgfont` **之外**） |
| `ThreadImageParser.isContentImage` | **不再要求同域**（老帖图多在外链图床，如 `pic.eawan.com`） |
| `PaginationParser.strippingSessionID` | PC 链接带 `&sid=…`，我们始终带 Cookie，必须剥掉 |
| `PostRepository` 附件上传 | PC 发帖页有 `form#imgattachform`，上传走 **SWFUpload 两步协议** |
| `DiscuzFormParser.attachmentUploadKeys` | 运行时解析该表单的 `uid` / `hash` |

⚠️ 历史夹具与 `analysis/probe.mjs` 仍是 WAP 口径：**夹具要两套都留**，
新抓页面一律用桌面 UA（`analysis/pcfetch.mjs`）。

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
**两个结论并不矛盾，只是看的不是同一套模板。** 项目里「入口被注释 ≠ 功能不存在」这条经验依然成立。
Sprint 18 起客户端虽然已经拿到 PC 模板，**但仍然直接用已知接口 + 回读确认**，
不依赖页面里的入口 —— 入口是给人点的，接口才是给程序调的，后者更稳。

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
WAP 登录门的文案就是「对不起，**您还未登录**，无法进行此操作。」，能被这条规则命中；
PC 模板的登录门文案同样含「您还未登录」（Sprint 18 复核），所以切换模板不影响这条检测。
（另注：登录门页面自己带一个 `logging.php?action=login` 的 `<form>` 和 `formhash`，
所以**任何「解析页面表单再提交」的流程都必须先确认不是登录门**，否则会把正文提交到登录脚本上。）

---

## 五、复现命令（本地免登录）

```bash
node analysis/uatest.mjs        # 对比 mobile / desktop / 裸 UA 各拿到哪套模板
node analysis/tpldiff.mjs "viewthread.php?tid=193033"   # 两套模板的关键词计数差
node analysis/probe.mjs "pm.php?action=view&uid=29"     # 游客可达性（结果会存到 _probe/）
node analysis/decode.mjs _probe/pm_wap.html             # GBK 页面解码 + 打印表单原文
node analysis/pcfetch.mjs "viewthread.php?tid=332225"   # 用**桌面 UA** 抓页面存成 *_pc.html 夹具
node analysis/verifypc.mjs                              # 用 cheerio 镜像 Swift 选择器，逐条校验 PC 夹具
```

⚠️ `analysis/probe.mjs` 刻意使用**移动 UA**，`analysis/pcfetch.mjs` 刻意使用**桌面 UA** ——
前者用于诊断可达性与历史结构，后者用于生成当前线上口径的夹具。
**两者都不等于「App 用什么」**：App 从 Sprint 18 起用桌面 UA（见 `HTTPClient.swift`）。

---

## 六、结论：模板问题对现有功能的影响

| 功能 | 现状 | 是否受模板影响 |
|---|---|---|
| 读帖正文 / 楼层 / 回复 / 发帖 / 收藏 / 关注 / 好友 / 私信 | 已实现 | **不受影响**（解析器 PC 优先 + WAP 兜底；写操作一律走已知接口 + 回读确认） |
| **列表首图预览** | ✅ **已修（07ed852）** | 全局 PC 模板后直接拿附件图地址；实测可用率 20% → 40%（真实可下载） |
| **详情页内嵌图片** | ✅ **已修（Sprint 18）** | 详情正文同样来自 PC 模板；`ThreadDetailParser` 把 `div.postattachlist img[file]` 的真实地址追加进楼层正文，`PostContent` 再提取成图片区 —— 列表与详情不再不一致 |
| **浏览量** | ✅ **新增（Sprint 18）** | PC 模板的 `td.nums > em` 输出浏览量（WAP 模板没有这个字段） |
| 附件上传 | ✅ 已按 SWFUpload 两步协议实现 | ⚠️ **待真机验证**：`form#imgattachform` 的 `uid`/`hash` 与 `misc.php?action=swfupload` 端点需登录后才看得到；失败会明确报「附件上传失败（帖子未发出）」 |
| 「关注」 | ✅ **已接入（Sprint 18）** | `my.php?item=attention`（参数 **tid**，关注的是**主题**）；「我的 → 关注」为主题型列表，详情页操作栏有铃铛 |
