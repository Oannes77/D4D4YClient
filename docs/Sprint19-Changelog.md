# Sprint 19 —— 验收图圈注的四处修改（首页发帖入口 / 详情图片 / 星标对齐）

> 来源：用户在 Sprint 18.1 验收图上圈了 4 处（其中 1 处是提问）。
> 本文只记「改了什么、为什么之前是那样、怎么验证的」。

## 一、操作栏六个图标分别是什么（提问，顺带留档）

用户问的「分别是什么功能」= 详情页楼层操作栏的六个图标。它们**只有图标没有文字**，
所以这里把「图标 → 功能」的对照写进 `Phase4-Screens.md` 的 UI 硬约定，避免下次再靠猜：

| 图标（SF Symbol） | 功能 | 真实动作 |
|---|---|---|
| `bubble.right` 对话气泡 | 回复 | 弹回复 Sheet |
| `arrowshape.turn.up.right` 弯箭头 | 分享 | 菜单二选一：系统分享 / **站内分享给好友**（发私信带链接） |
| `star` / `star.fill` 星 | 收藏 | 写**论坛服务器**收藏（`my.php?item=favorites&type=thread`），回读确认 |
| `bell` / `bell.fill` 铃铛 | 关注 | 关注**本主题**的新回复（`my.php?item=attention&action=add&tid=<tid>`），回读确认 |
| `exclamationmark.bubble` 带感叹号的气泡 | 举报 | 复制该帖链接 + 私信管理员（默认 UID 29 / 4D4Y） |
| `safari` 圆圈指南针 | 网页版 | 浏览器打开该帖（站内评分等只在网页端提供） |

⚠️ `safari` 图标在细线单色下容易看成「禁止 / 拉黑」（`nosign`）。这一条已在文档里注明，
若后续觉得误读率高，最省事的改法是换成 `globe`。

## 二、收藏列表的星标没对齐

**现象**（用户圈图）：`我的收藏` 每行右侧，金色 ★ 比右侧的「›」低一整行。

**原因**：`SavedThreadsView.row` 里星标是这么摆的 ——

```swift
VStack(alignment: .leading) {
    Text(item.title)          // 第 1 行
    HStack { Text(item.detail); Spacer(); Image("star.fill") }  // 第 2 行 ← 星标在这里
}
```

而 `NavigationLink` 的「›」是**按整个 cell 垂直居中**的 ⇒ 一个居中、一个在第 2 行，
自然错开。

**改**：星标移到行尾、与「›」同在行的垂直中线（标题/详情留在左侧 VStack 里）：

```swift
HStack(spacing: 10) {
    VStack(alignment: .leading, spacing: 6) { title; detail }
    Spacer(minLength: 8)
    Image(systemName: "star.fill").font(.footnote).foregroundStyle(.appGold)
}
```

## 三、楼层多图排成「方块墙」很难看

**现象**（用户圈图）：首帖 5 张附件图排成「3 张一行 + 2 张一行」的小方块，宽窄高矮不齐。

**原因**：`PostContent.imagesGrid` 用的是

```swift
LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8)
… .frame(height: 120) + .scaledToFill()      // 每格 120pt 高、填满即裁切
```

`adaptive(minimum: 110)` 会塞下尽可能多的列（本机 3 列），`scaledToFill` 又把每格填满后裁掉两边 ——
论坛附件多是**竖拍照片或整屏截图**，裁成小方块后既看不清内容，一行里的行高又不一致。

**改**：改成竖排，**一张一行、按原始比例铺满可用宽度**（`scaledToFit` 不裁切）。
加载中给一块 180pt 的占位（不是零高度），避免图片到达时整页高度跳变。
点击任一张仍进全屏画廊左右滑 —— 行为不变，只是版面变了。

## 四、首页：搜索栏改成「默认收起 + 下拉出现」，腾出的位置放发帖入口，取消 FAB

用户的原话：
> 「我们讨论过首页的搜索框，是放在最上面，下拉才会出来。正常是缩进去的。」
> 「如果搜索能缩进去，那就在现在搜索的位置加入，threads 类似的发帖模块，点击后切换到发帖页面，
>   现在的紫色悬浮发帖按钮就可以取消。」

### 4.1 搜索栏：从「上推隐藏」改成「下拉出现」

原来的驱动条件是「静止时可见、上推才隐藏」：

```swift
searchCollapsed = y < -8     // 滚过顶 8pt 就收起；在顶部则一直露着
```

现在倒过来 —— **默认收起**，只有**下拉回弹**（内容被拽过顶）才展开：

```swift
@State private var searchCollapsed = true          // 初始即收起

.onPreferenceChange(ScrollOffsetKey.self) { y in
    if y > 4, searchCollapsed       { searchCollapsed = false }   // 下拉 → 展开
    else if y < -4, !searchCollapsed { searchCollapsed = true }   // 上滚 → 收起
}
```

两个阈值分开、中间不动作，回弹到位时不会反复抖。`CollapsibleSearch` 组件本身没动
（它本来就支持「收起时高度 0 + clipped」），只换了触发条件。

### 4.2 新增 `Shared/ComposeEntryBar.swift`（Threads 风格发帖入口）

摆在此前搜索框的位置：**当前用户头像 + 「发新帖…」胶囊**，整行可点，点进发帖页。
未登录 / 拿不到 uid 时头像走 `AvatarView` 的中性默认图标（不伪造真人头像），
`uid <= 0` 时直接传 nil，不白发一个必然 404 的头像请求。

### 4.3 取消右下角紫色悬浮按钮

- `HomeView` 去掉 `.overlay(alignment: .bottomTrailing) { ComposeFAB … }`；
- **删除 `Shared/ComposeFAB.swift`**（唯一引用点就是首页，不留死代码）。

**连带收益**：Sprint 18.1 遗留的「FAB 压住第 2 条标题与摘要」这个悬而未决项，随之消失。
这是悬浮按钮的固有代价 —— 只要它固定在右下角，就一定会盖住滚动内容。

### 4.4 待人工验证

搜索栏「下拉才展开」是**手势驱动的动效**，静态截图拍不到两种状态。
本轮没有为它新增截图界面（`-DemoScreen` 只能直渲一个固定状态）。
真机 / 模拟器上手滑一下即可确认；若长时间看不出来，再考虑加
`-DemoSearchExpanded` 之类的截图参数把展开态也钉进验收清单。

## 五、验证与影响面

- 静态检查：`swiftcheck`（括号）+ `swiftlint-lite`（成员初始化器标签 / OSLog 拼接 / 冗余 `try?`）
  + `dups`（符号重名），全部 0 问题。
- 改动文件：`Features/Home/HomeView.swift`、`Features/Thread/PostContent.swift`、
  `Features/Profile/SavedThreadsView.swift`、新增 `Shared/ComposeEntryBar.swift`、
  删除 `Shared/ComposeFAB.swift`；
  文档：`docs/Phase4-Screens.md`（UI 硬约定 4 条 + 操作栏图标对照 + 截图核对判据纠错）。
- **没动**的部分：解析器、网络层、演示夹具、发帖页 `NewPostView`（仍按原样以 sheet 弹出）、
  收藏 / 关注的服务器读写逻辑。
- 验收清单仍为 10 界面 = 20 张（`home` 界面现在会拍到「板块胶囊 + 发帖入口 + 首条帖子」，
  搜索栏收起——这正是本轮要验的形态）。
