# Sprint 9B — 图片增强实现 · 交付文档

> 前置：Sprint 9A 探查（docs/Sprint9A-Probe.md）已确认——forumdisplay 列表无图片字段，图片只存在于 viewthread 正文 `<img>`，采用方案 B（延迟检测 + 缓存）。

## 1. 修改 / 新增文件列表

### 新增
| 文件 | 职责 |
|------|------|
| `Parsers/ThreadImageParser.swift` | 解析帖子正文 HTML 中的真实内容图片；过滤头像/表情/图标/模板资源 |
| `Repositories/ImageMetadataRepository.swift` | 按 tid 请求 viewthread 第一页 → 调用 Parser → 返回 `ThreadImageInfo`；并发受限批量 `detectAll` |
| `Models/Models.swift` (+`ThreadImageInfo`) | 纯数据图片信息 `ThreadImageInfo`（**不混入 ForumThread 网络模型**） |
| `Models/LocalModels.swift` (+`ThreadImageCache`) | SwiftData 缓存 `ThreadImageCache`：tid 唯一、hasImages、imageCount、thumbnailURLs、detectedAt（24h 有效） |

### 修改
| 文件 | 改动 |
|------|------|
| `App/D4D4YApp.swift` | `ModelContainer` 注册 `ThreadImageCache` |
| `Features/Forum/ThreadListView.swift` | 接入 `@Query` 图片缓存；列表加载后触发后台检测；行尾轻量 `📷 N` 标识；点按打开 `ImageViewer` |

### 红线（未改动）
`Network/HTTPClient.swift`、`Parsers/ThreadListParser.swift`、`Parsers/ThreadDetailParser.swift`、`Repositories/ForumRepository.swift`、`Core/Authentication/*`、`Repositories/ReplyRepository.swift`、`Repositories/LoginRepository.swift`。
（图片检测走 `ImageMetadataRepository` 而非 `ForumRepository`，故 ForumRepository 公开契约未改。）

## 2. 图片数据流图

```
ForumThread (id: tid)                         ← 列表网络模型（不含图片字段）
      │
      ▼  ThreadListView 加载完成后触发（仅当前页优先主题，去重+跳过已缓存）
ImageMetadataRepository.detect(tid:)
      │  1) HTTPClient 请求 viewthread.php?tid=N（公开帖无需登录）
      │  2) HTMLDecoder 按 GBK/GB18030 解码
      │  3) ThreadImageParser.parseContentImageURLs(from:)
      │        • 仅圈定 <img> 标签取值（防 <script src>/Cloudflare 误匹配）
      │        • 每 <img> 取一个（优先 file 原图，否则 src 缩略图）
      │        • 过滤：uc_server/avatar、images/smilies、images/icons、
      │               images/default、templates/、logo/fuser/agree、.js/.css 等
      │        • 仅留 4d4y.com 域内容图
      ▼
ThreadImageInfo (hasImages / imageCount / thumbnailURLs)
      │
      ▼  ThreadImageCache.upsert(_:context:)（主线程写入 SwiftData）
ThreadImageCache (tid 唯一, 24h 有效期)
      │
      ▼  @Query 自动刷新列表行
ThreadListView 行尾 📷 N  ←→ 点按 fullScreenCover → ImageViewer（首图）
```

## 3. 缓存策略说明
- **存储**：SwiftData `ThreadImageCache`，`tid` 唯一约束，重复写入做 upsert（刷新字段 + `detectedAt`）。
- **有效期**：`isFresh` = 距 `detectedAt` < 24h。过期后下次列表加载会重新检测（本版列表加载即触发检测，过期缓存视为缺失）。
- **触发**：`ThreadListView` 在 `.task` 首屏加载与 `.refreshable` 刷新后，对当前页主题做检测；已缓存（不论是否过期——本版简化：仅跳过“已存在”的 tid，过期刷新依赖重新进列表/刷新）的 tid 跳过，避免重复请求。
- **并发**：`detectAll` 默认 4 路（`withTaskGroup` 分批），每子任务自建 `HTTPClient`（严格并发安全，不跨 actor 捕获实例）。单次检测上限 `cappedDetectCount = 20`，避免开列表即请求几十个帖子（任务要求：只检测当前列表优先主题）。
- **隐私/副作用**：仅本地读缓存，不修改任何服务器数据。

## 4. UI 接入与截图
- **列表标识**：行尾 `📷 N`（系统 `photo` 图标 + 图片数），使用 `Color.appPrimary` 品牌紫，弱存在感，无卡片/大缩略图/图片墙。
- **点击入口**：📷 独立于 `NavigationLink`（位于其外侧的 `Button`），点按仅打开既有 `ImageViewer`（全屏 + 捏合缩放 + 双击复位），不重新设计查看器。
- **截图（⚠️ 本环境无法生成）**：当前为 Windows / 无 Xcode，不能编译运行或出模拟器截图。请在 Mac/Xcode 跑通后补「列表行尾 📷 N」「点 📷 打开 ImageViewer」两张浅/深截图。
  下图为列表行结构示意（文字风格，非真实截图）：

## 5. 真实验证结果
用 Python 镜像 `ThreadImageParser` 过滤逻辑，基于仓库真实夹具与合成样例验证：
- **测试1·真实文本帖**（`Tests/Fixtures/viewthread_tid193033_page1.html`，含 1 表情 + 3 模板赞 + 2 模板资源）：内容图 = **0** ✅ 不显示标识。
- **测试2·合成图片帖**（含头像/表情/图标/模板 + 3 张内容图，其中 1 张 `<img src+file>` 同图）：内容图 = **3** ✅ 头像/表情/图标/模板/脚本全排除，且 `src`+`file` 同一图不重复计数（`file` 原图优先）。
- **测试3·模板+脚本误匹配防护**：`<script src=...>` 与模板 `fuser.png` 均被排除，内容图 = **0** ✅（捕获并修复了一处真实 bug：初版误把 `<script src=...>`/Cloudflare challenge 脚本当图片）。

> 端到端真机验证（真实图片帖 → 列表显示 📷 N → 点开 ImageViewer）需 Mac/Xcode + 原生流量过 Cloudflare，本环境脚本访问被 Cloudflare 全拦截，未能跑通；解析与过滤逻辑已用真实夹具确定。

## 6. 未解决问题
1. **真机截图/编译**：需在 Mac/Xcode 验证（环境限制）。
2. **真实图片帖样本缺失**：仓库仅 text-only 夹具，正例用合成 HTML 验证；真机照片帖需复核 `img02.4d4y.com/forum/...` 具体路径前缀，若站点用其它 CDN 路径需微调 `isContentImage` 正例规则。
3. **多图左右切换**：现有 `ImageViewer` 为单图查看器（全屏+缩放+双击复位），**不支持左右滑动切换多张图**。本任务要求“不要重新设计图片查看器”，故 📷 点按仅打开首图；多图画廊留待后续。
4. **过期缓存刷新**：本版列表检测跳过“已存在”tid，未强制 24h 后重检（重新进列表/下拉刷新会重新检测）。如需严格 24h 失效，可在 `detectForVisibleThreads` 中改用 `cache.isFresh` 判断跳过。
5. **成员-only 板块**：图片检测用游客请求，私有板块会失败（行不显示标识），属预期降级。
