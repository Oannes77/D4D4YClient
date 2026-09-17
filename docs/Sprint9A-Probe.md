# Sprint 9A · 图片增强系统探查报告

> 阶段性质：**仅数据探查，未写 UI、未改模型、未改红线文件。**
> 探查对象：4D4Y 真实 `forumdisplay.php`（主题列表）与 `viewthread.php`（帖子正文）HTML。

---

## 0. 探查方法与数据来源（重要）

- **实时抓取被 Cloudflare 拦截**：本环境（Windows / 无 Xcode）当前对 `www.4d4y.com` 的脚本访问被 Cloudflare 全面拦截——
  - `GET logging.php?action=login` → 6KB Cloudflare 拦截页；
  - `GET forumdisplay.php?fid=14` → 间歇返回 10KB 非论坛页，或 TLS `UNEXPECTED_EOF_WHILE_READING`（连接被重置）。
  - 结论：**本环境无法实时抓取真实 HTML**，需在有原生流量放行的真机 / Mac 上执行实时探针。
- **改用真实缓存样本**：采用此前 Sprint 抓取并随仓库发布的真实 4D4Y HTML 夹具（这些就是真实页面，非假设）：
  - `Tests/Fixtures/forumdisplay_fid14_page1.html`（72,689 字节）
  - `Tests/Fixtures/forumdisplay_fid14_page2.html`（74,531 字节）
  - `Tests/Fixtures/viewthread_tid193033_page1.html`
  - 合计分析 **150 条主题行 + 1 个帖子详情页**。
- 解析器 `Parsers/ThreadListParser.swift` 头部注释也明确记录了真实 DOM 结构（已用 fid=14 第 1/2 页验证），作为交叉佐证。

---

## 1. 4D4Y 主题列表 HTML 探查结果

对 `forumdisplay` 两页共 150 个主题行逐行扫描：

| 检查项 | 主题行内出现次数 |
|---|---|
| `<img>`（头像 / 类型图标） | 每个主题行 1~2 个 |
| 其中头像 `uc_server/data/avatar/..._avatar_small.jpg` | 每个主题行 1 个（作者头像） |
| 其中 Discuz 类型图标 `images/icons/iconN.gif` | 部分行 1 个（精华/置顶/普通状态） |
| `attach` / `attachment` | **0** |
| `[img]` / `[image]`（BBCode） | **0** |
| `图` / `贴图` / `有附件` / `t_attach` / `icon_clip` | **0** |
| 内容缩略图 / 附件缩略图 URL | **0** |

**关键事实**：主题行 `<tr>` 的真实结构（`Parsers/ThreadListParser.swift` 已验证）为
`td.list_user`（头像）+ `td.listcon`（作者/日期/分类/标题）+ 回复数 `<a class="num">`。
**行内没有任何图片 / 附件 / 缩略图信息，也没有"图片数量"字段。**

---

## 2. 是否存在图片信息？

- **主题列表（forumdisplay）：不存在图片信息。** 既不能得到 `hasImages`，也不能得到 `imageCount` 或 `thumbnailURLs`。
- **图片真实位置在帖子详情（viewthread）**：正文以 `<img>` 渲染。对 `viewthread` 样本检查：
  - `[img]` / `[attach]` BBCode = **0**（当前 wap 模板已把媒体预渲染为 `<img>`）；
  - `<img>` 来源包括：表情 `images/smilies/...`、头像、模板资源，以及来自 `img02.4d4y.com/forum/` 的内容图（样本中出现 5 次）。
  - 即：帖子内的真实图片是**渲染后的 `<img>`**，需从 `Post.htmlContent` 中提取并过滤掉头像/表情/图标/模板资源。

---

## 3. 推荐方案：方案 B（延迟检测）

排除依据：
- **排除方案 A**：主题列表 HTML 无图片字段，无法"直接扩展 `ThreadListParser`"得到 `ThreadImageInfo`。（证据见第 1、2 节）
- **排除方案 C 作为主路径**：当前 wap 模板不输出 `[img]`/`[attach]` BBCode，图片已是 `<img>`； BBCode 解析仅作为 `ImageMetadataRepository` 内的**防御性兜底**（极少数旧帖 / 全文模板可能残留），不作为主逻辑。

**采用方案 B：延迟 / 后台检测 + 缓存。**

流程（与产品目标一致）：
```
ThreadList 展示
   └─ 列表加载后，对"尚未检测过"的 tid 触发后台检测（并发受限）
        └─ ImageMetadataRepository.fetch(tid)
             └─ GET viewthread.php?tid=N&page=1（复用 HTTPClient + 登录态）
             └─ 解析 Post.htmlContent 中 <img>（排除头像/表情/图标/模板资源）
             └─ 得到 ThreadImageInfo { hasImages, imageCount }
        └─ 写入缓存（SwiftData 或内存字典，按 tid）
   └─ ThreadList 读取缓存，已检测线程显示 📷 N 标识
用户点开线程 → ThreadDetail 解析时亦回写该 tid 的图片信息（幂等）
```

**首页 9A 阶段不做 UI**，但确定 UI 契约（供后续 Sprint）：
- 主题列表：保持论坛文字列表，**不**用图片卡片 / 大缩略图。
- 推荐呈现：`📷 N`（如 `📷 12`），放在标题/作者行下方或行尾，颜色用 Theme 次文本色，不抢标题。
- 点击 📷 标识：打开 `ImageViewer`（已有）看该帖图片，序号从缓存的 thumbnailURLs 取。

---

## 4. 数据模型调整建议（仅建议，本阶段不改）

- `ForumThread`（Models.swift）建议新增：
  - `hasImages: Bool = false`
  - `imageCount: Int = 0`
  - （可选）`thumbnailURLs: [URL]?` —— 仅用于点击 📷 后预览；列表 UI 不展示缩略图。
- 新增缓存模型（SwiftData，`LocalModels.swift`）：
  - `ThreadImageCache`: `{ tid: Int, hasImages: Bool, imageCount: Int, thumbnailURLs: Data?, detectedAt: Date }`
  - 主键 `tid`；`ImageMetadataRepository` 读写。
- 新增值类型（可选）：
  - `ThreadImageInfo { hasImages, imageCount, thumbnailURLs }`，作为 Repository 返回值与缓存中间结构。

---

## 5. 预计修改文件列表（实现 Sprint 用，本阶段未改）

新增：
- `Repositories/ImageMetadataRepository.swift`（NEW）— 抓取并解析图片元数据，读写缓存。
- `Parsers/ThreadImageParser.swift`（NEW）— 从 `Post.htmlContent` 提取 `<img>`（复用现有解析helper，不改 Parser 核心协议）。
- `Models/LocalModels.swift` — 新增 `ThreadImageCache`（SwiftData）。

修改（实现 Sprint 才动）：
- `Models/Models.swift` — `ForumThread` 增加 `hasImages` / `imageCount`。
- `Repositories/ForumRepository.swift` — 列表加载后调度后台图片检测（或仅暴露 `imageInfo(for:)` 查询接口，由 ViewModel 调度）。
- `Features/Thread/ThreadDetailViewModel.swift` — 解析完成后回写 tid 图片信息（幂等）。
- `Features/Forum/ThreadListView.swift` — 展示 📷 N 标识（后续 Sprint 的 UI 任务）。

**红线（本次及实现 Sprint 均不修改）**：
`Network/HTTPClient.swift`、`Parsers/` 核心协议（`Parser` 协议本身）、`Repositories/ForumRepository.swift` 的现有公开接口契约、`Core/Authentication/*`、`Repositories/ReplyRepository.swift`。

---

## 6. 待真机确认的风险点

1. **实时抓取需在真机验证**：Cloudflare 当前拦截脚本，方案 B 的后台检测依赖原生流量放行（Sprint 7B 已证明真机/原生可过 CF）。
2. **照片帖样本缺失**：现有夹具 `tid=193033` 非图片帖（仅含表情图）。实现时需用真机对一个真实摄影/图片帖验证 `<img>` 提取与过滤规则（尤其区分"真实附件图"与"表情/图标"）。
3. **后台检测性能**：列表一次加载数十帖，需限制并发（建议 3~4 路）并去重，避免请求风暴与被封。
4. **缓存失效**：帖子新增图片后缓存过期策略（建议按 tid + 检测时间戳，24h 内复用）。

---

## 结论

- 主题列表 HTML **不含**图片信息 → **方案 A 不可行**。
- 图片在帖子正文 `<img>` 中 → **方案 B（延迟检测 + 缓存）为推荐路径**，方案 C 仅作防御性兜底。
- 本阶段只产出探查结论，未触碰任何源码与红线文件。下一步进入"图片增强实现 Sprint"时，按第 5 节文件清单落地。
