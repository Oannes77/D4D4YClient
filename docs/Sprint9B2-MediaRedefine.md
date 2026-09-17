# Sprint 9B2 · 图片功能重新定义（列表轻量媒体标识）

> 基于 Sprint 9A 探查 + Sprint 9B 实现，按最新产品定义**重定义**媒体感知：
> 列表不是图片浏览系统，只是提升帖子点击欲望的轻量标识。

## 1. 产品定义落地

| 标识 | 含义 | 列表行为 |
|------|------|----------|
| 📷 `camera.fill` | 正文存在有效图片 | 显示；**点按预览第一张有效正文图片**（复用既有 ImageViewer） |
| 📎 `paperclip`   | 正文含附件（文件型） | 显示；**列表不预览**，进入帖子后查看 |

**明确不做**（遵守红线）：
- 不显示图片数量（去掉 `imageCount`）
- 不显示多图缩略图（去掉 `thumbnailURLs`）
- 不显示图片墙 / 复杂图片系统
- 完整图片浏览只属于 `ThreadDetail`（本阶段未改 ThreadDetail）

## 2. 数据模型重定义

**`Models/Models.swift` — `ThreadMediaInfo`（取代 `ThreadImageInfo`）**
```swift
struct ThreadMediaInfo: Hashable {
    let tid: Int
    let hasImage: Bool          // 正文存在有效内容图片
    let previewImageURL: URL?   // 第一张有效正文图（点击 📷 预览用）
    let hasAttachment: Bool     // 含附件（文件型）
}
```

**`Models/LocalModels.swift` — `ThreadMediaCache`（取代 `ThreadImageCache`，SwiftData）**
- `@Attribute(.unique) tid`
- `hasImage: Bool`
- `previewImageURL: String?` + 计算属性 `previewURL: URL?`
- `hasAttachment: Bool`
- `detectedAt: Date`，`isFresh`（24h）
- `upsert(_:context:)` / `cache(for:context:)` 静态方法

`D4D4YApp.swift` 容器注册由 `ThreadImageCache.self` 改为 `ThreadMediaCache.self`。

## 3. 解析与检测（Parsers/ThreadImageParser.swift）

- `parseContentImageURLs(from:)` —— 仅圈定 `<img>` 内取值，过滤头像 / 表情 / 图标 / 模板资源，
  同图 `src+file` 只取一个；返回内容图 URL（保持原逻辑）。
- **新增** `detectHasAttachment(from:)` —— 命中 `attachment.php?aid=` 下载链接 或 `[attach]`/`[attachimg]` BBCode 即判为含附件。
  - 图片型附件已在 `parseContentImageURLs` 中被识别为 `hasImage`，不重复计入 `hasAttachment` 误判；
    但图片帖同时含文件附件时两者可同时为真（均为诚实标识）。

## 4. 仓库（Repositories/ImageMetadataRepository.swift）

- `detect(tid:)` / `detectAll(...)` 返回类型由 `ThreadImageInfo` 改为 `ThreadMediaInfo`，
  内部组合 `parseContentImageURLs` + `detectHasAttachment`。
- 并发受限（4 路）、子任务自建 HTTPClient、遇 Cloudflare 立即失败——均不变。

## 5. 列表接入（Features/Forum/ThreadListView.swift）

- `@Query var imageCaches: [ThreadMediaCache]`
- 行尾 `HStack` 独立承载媒体标识（不破坏 NavigationLink / 行内文字风格）：
  - `cache.hasImage && cache.previewURL` → `Button { Image(systemName: "camera.fill") }` 点按 `presentedImage = FullScreenImage(url:)`
  - `cache.hasAttachment` → 被动 `Image(systemName: "paperclip")` 指示（列表不预览）
- 后台检测 `detectForVisibleThreads()` 逻辑不变（并发 4、去重、上限 20、upsert 入缓存）。

## 6. 红线（未改）

`HTTPClient` / `Parsers` 目录其它解析器 / `ForumRepository` 公开契约 / `Authentication` / `ReplyRepository` / `LoginRepository` / `ThreadDetailView` 均**未修改**。
图片检测仍走 `ImageMetadataRepository`，`ForumRepository` 契约未动。

## 7. 真实验证（Python 镜像解析逻辑，基于真实夹具）

- **真实文本帖** `viewthread_tid193033`（1 表情 + 3 模板赞 + 2 模板资源）→ `hasImage=false, hasAttachment=false`，列表**不显示任何标识** ✅
- **合成图片帖 + 文件附件** → `hasImage=true`，`previewImageURL` = 首张内容图（`.../photoview/abc123.jpg`），`hasAttachment=true`；
  头像 / 表情 / 图标 / 模板资源全部排除，📎 命中 `attachment.php?aid=` ✅
- **仅文件附件（无图）** → `hasImage=false, hasAttachment=true` ✅

## 8. 未解决问题

1. **真机编译 / 截图**：本环境 Windows + 无 Xcode，无法编译运行或出模拟器截图；请在 Mac/Xcode 跑通后补「列表行尾 📷 / 📎」「点 📷 开 ImageViewer 首图」两张浅/深截图。
2. **附件检测样本缺失**：仓库无真实含附件的 viewthread 夹具，`detectHasAttachment` 基于 4D4Y 常见结构（`attachment.php?aid=` / `[attach]` BBCode）防御性实现，需在真机用真实附件帖复核，避免模板页脚误命中。
3. **图片帖同时含文件附件时双标识**：📷 与 📎 会同时出现（语义诚实），若产品希望图片帖只显示 📷，可在 `detectHasAttachment` 中排除「图片型附件」，需产品确认。
4. **多图浏览**：点击 📷 仅预览第一张（复用单图 ImageViewer）；多图画廊 / 完整图片浏览留给 `ThreadDetail` 后续。
5. 缓存刷新策略：当前 `detectForVisibleThreads` 跳过「已存在」tid（首进/下拉刷新重检），未强制 24h 失效；如需严格失效改用 `cache.isFresh` 判断。
