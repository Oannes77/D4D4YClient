# 修复：截图 workflow 连续 0 张图（build #55 / commit `9b9c88a`）

> 2026-09-28。**这不是一次普通的功能迭代，是一次流程事故的收尾**：
> 从 Sprint 21 起，截图 workflow 连续 4 个 Sprint 产出 **0 张图**，而构建一直是**绿的**。

## 一、现象

拿到的截图产物目录里只有两个元数据文件、**一张 png 都没有**：

```
screenshots/
  manifest.json    4 B   ->  []          （空数组）
  runinfo.txt     90 B   ->  commit=9b9c88a… / branch=main / build=55 / workflow=screenshots
```

`collect_screenshots` 日志自己也点出了根因：

```
--- png 数量: 0 ---
!!! 警告：未导出任何 png 截图。常见根因是主 App / 测试 target 编译失败，
!!! 导致 xcodebuild 并未真正运行 UI 测试（即使上面步骤显示 '完成'）。
756: …/Features/Home/HomeView.swift:75:32: error: cannot find 'lockedBoardIDs' in scope
759: …/Features/Home/HomeView.swift:156:29: error: cannot find 'demoNotice' in scope
762: …/Features/Home/HomeView.swift:316:27: error: cannot find 'isGuest' in scope
769: …/HomeViewModel.swift:111:26: error: type 'HomeViewModel.FeedState' has no member 'notice'
```

**不是截图机制坏了，是主 App 根本没编译过。**

## 二、根因

### 2.1 直接原因：Sprint 21 的半截提交（4 处符号只有调用点、没有定义）

`git log -S` 追踪到全部 4 处都来自 `1dd9fd0`（Sprint 21「识别登录门给真实登录出口」）：

| 位置 | 引用 | 事实 |
|---|---|---|
| `HomeView.swift:75` | `lockedIDs: lockedBoardIDs` | 属性**从未被定义** |
| `HomeView.swift:156` | `if let notice = demoNotice` | 属性**从未被定义** |
| `HomeView.swift:316` | `isGuest ? …` | 属性**从未被定义** |
| `HomeViewModel.swift:111` | `state = .notice(SiteNotice(alert:))` | `FeedState` 少了 `case notice(SiteNotice)` |

那次提交的 message 明写着「`HomeViewModel.FeedState` 增 `.notice(SiteNotice)`」，
但 `git show` 的 diff 里**没有这一段** —— 调用点改了、定义漏了，典型的半截编辑。

### 2.2 隐藏的第 5 处：CI 从来没走到那一步

`Shared/ScreenshotRoute.swift:78/95` 用了 `ScreenshotScreen.boardLoginGate`，
而枚举里**同样没有这个 case**。它之所以没出现在日志里，是因为
**Swift 是分批（batch）编译的**：第 8 批（`DiscuzFormParser`…`Loadable`）就报了那 4 个错，
driver 直接停止调度后续批次 —— `ScreenshotRoute.swift` 所在的批次**根本没轮到**。

⇒ 只修日志里那 4 个错、重跑一次 CI，必然再挂一轮。**必须把同因问题一次修完。**

### 2.3 为什么 4 个 Sprint 都没发现（真正贵的地方）

1. **本地三个静态检查全部「通过」**：`swiftcheck`（括号 0 问题）、`dups`（无重名）、
   `swiftlint-lite`（无标签/OSLog 问题）—— 它们查的都是「括号 / 标签 / 重名」，
   **没有一条能查「这个符号压根不存在」**。
2. **`xcodebuild test … || true` 把编译失败静默吞掉**（这是刻意设计，为了让 Collect 步骤
   还能导出已有截图）。于是 workflow 一路走到绿。
3. **0 张图只是一个 `echo` 警告，不影响构建结论** ⇒ 「绿的构建 + 空产物」这种最贵的假象，
   可以无限期地滑过去。Sprint 21 / 22 / 23 / 24 的「已完成」都建立在没有证据之上。

## 三、修复内容

### 3.1 代码（5 处）

| 文件 | 修复 |
|---|---|
| `Features/Home/HomeView.swift` | 补 `isGuest`（`!(已登录 \|\| 演示模式)`）、`lockedBoardIDs`（游客时 = `ForumBoards.loginOnlyFIDs`）、`demoNotice`（演示模式读 `DemoOverrides.shared.homeNotice`）；新增 `@ObservedObject session` / `demoOverrides` 让登录态与注入状态能触发重绘 |
| `Features/Home/HomeViewModel.swift` | `FeedState` 增 `case notice(SiteNotice)`，与 `.failed` 严格分开（「服务器拒绝了这次访问」≠「解析失败」≠「真的没有内容」） |
| `Shared/ScreenshotRoute.swift` | `ScreenshotScreen` 增 `case boardLoginGate`（截图清单里早就在用了，只有枚举漏了） |

设计中特意保守的一点：`isGuest` 在**演示/截图模式下恒为 false**。
`bootstrap()` 在演示分支就已 `return`，`ScreenshotRouteView` 也会 `enterDemoSession()`；
若不这样写，首页截图会凭空多出两把锁 —— 而演示会话本来就不是游客。
（`ForumBoards.firstReadableForGuest` 只在真实游客路径上生效。）

### 3.2 工具：给 `swiftlint-lite` 补上「查不到的那一半」

新增 **[D] 未声明标识符检查（硬错误）** —— 用「仓库内自洽推断」逼近编译器的
`cannot find 'X' in scope` / `has no member 'x'`：

- **D1 裸标识符**：一个名字只要在**整个仓库的任何声明位置**出现过就不报；
  从未出现过 ⇒ 报错。（对应 `lockedBoardIDs` / `demoNotice` / `isGuest`）
- **D2 隐式成员**：`case .foo` / `== .foo` 里的 `.foo` 不是任何声明过的名字 ⇒ 报错。
  （对应 `case .boardLoginGate`）
- 顺带修掉一个会污染判断的解析 bug：**字符串插值 `\( … )` 没有递归处理**，
  导致 `"\(a ? "light" : "dark")"` 在内层引号处被当成字符串结束，插值里的代码被当源码扫描
  ⇒ 误报「`light` 未声明」。现在插值内部按代码递归处理，并补上原始字符串 `#"…"#`。

配套 **自检脚本** `analysis/lint-selftest.sh`（`lint-selftest/bad/` 必须命中 3 处、
`lint-selftest/good/` 必须 0 误报）—— **一个查不到真问题的检查器比没有检查器更危险**。

> 检查器已知边界（宁可漏报不可误报）：同一名字在别处另有定义就查不出来。
> 例：`FeedState` 缺 `case notice` 这次**没被 [D] 抓到**（`notice` 在 `MessageChatViewModel`
> 里是个属性名）。所以它替代不了真实编译，只是把「忘了定义」这类错前移到了本地。

### 3.3 CI：0 张图必须让构建变红

`codemagic.yaml` 的 Collect 步骤末尾新增硬门禁：`PNG_COUNT == 0` ⇒ 打印 error 摘要后 `exit 1`。
（若 error 摘要为空，则是 runner / 模拟器偶发故障，重跑即可 —— 也会明确写出来。）

## 四、本地验证（无 Xcode，靠静态检查 + 选择器镜像）

| 检查 | 结果 |
|---|---|
| `swiftcheck.mjs`（括号 / 引号平衡） | 问题文件 **0** |
| `dups.mjs`（顶层符号重名） | **175** 个符号无重名 |
| `swiftlint-lite.mjs`（标签 / OSLog / 冗余 try? / **未声明标识符**） | 硬错误 **0**、警告 **0** —— 修复前是 **5**（3 个裸标识符 + 2 处 `.boardLoginGate`） |
| `lint-selftest.sh`（检查器自检） | 3 处故意错误全部命中、合法写法 **0 误报** |
| `verify20 / 21 / 22 / 23 / 24.mjs`（选择器镜像） | 全部通过（含登录门 21 项、编辑页 11 项） |
| `yamlcheck.cjs`（codemagic.yaml 解析） | 解析成功，2 个 workflow / 9 步 |

## 五、遗留 / 下一步

1. **触发一次 Screenshots workflow** 验收到 26 张图（13 个目标 × 亮/暗）。
   回来的第一件事仍是**验出身**：看 `runinfo.txt` 的 commit 是不是这一版，
   再用极差（1% / 99% 分位亮度差）判「有没有渲染」，最后才肉眼复核。
2. `alpha-build` 的 run-test 步骤写着「失败可忽略」—— 单测 target 在截图 workflow 里
   **根本不会被编译**，所以新写的断言（Sprint 24 的 2 条）目前只被 `verify24.mjs` 镜像验证过。
   要么把这一步改成硬失败，要么固定用 `verifyNN.mjs` 复验期望值。
3. Sprint 21–24 的「功能已完成」结论都缺少截图证据，建议在下一轮做一次**全量回归**
   （`SCREENSHOT_FULL=1`）补齐。

## 六、后记（build #56）：半截提交还有第三处漏网

> 2026-09-28 晚。上轮修复（`bda9994`）推上去后触发 Screenshots，build #56 **又挂了**：

```
708: …/ThreadDetailViewModel.swift:26:9: error: cannot find 'notice' in scope
711: …/ThreadDetailViewModel.swift:63:9: error: cannot find 'notice' in scope
714: …/ThreadDetailViewModel.swift:77:13: error: cannot find 'notice' in scope
```

### 6.1 根因：同一份半截提交，第三个文件

`1dd9fd0`（Sprint 21）在 `ThreadDetailViewModel` 里写了 `notice = SiteNotice(alert:)`
和 `notice = nil`（`fail(_:)` 里），但**从没声明 `notice` 属性**；`ThreadDetailView`
也挂了 `showLogin` sheet 却从没触发。上一轮只修了 HomeView / HomeViewModel / ScreenshotRoute，
**漏了这个文件**——它被分批编译挡在了 HomeView 之后，第 8 批报错后就没轮到。

### 6.2 为什么上轮的检查器 [D] 没抓到

上一轮 [D] 的判据是「一个名字只要在**整个仓库任何位置**出现过就不报」（宁可漏报不可误报）。
而 `notice` 恰好是个**高频实例属性名**：MessageChatViewModel（`@Published`）、NewPostView（`@State`）、
EditPostView（`@State`）、ShareToBuddySheet（`@State`）、HomeViewModel（`case notice`）……
于是它进了全局集合，`ThreadDetailViewModel` 里的裸 `notice` 被判「已知」⇒ **漏报**。

「全局集合」这个策略本身就是漏报温床：**实例属性、局部变量、枚举 case 名都不是跨文件可见的**，
把它们塞进全局集合，等于主动放过「跨文件同名未声明」这类 bug。

### 6.3 修复

| 项 | 内容 |
|---|---|
| 代码 | `ThreadDetailViewModel` 补 `@Published private(set) var notice: SiteNotice?`；`ThreadDetailView` 的 `.failed` 分支消费 `notice`，登录门给「登录」出口（触发已有的 `showLogin`），消除死代码 |
| 检查器根治 | [D] 的声明名按**跨文件全局 vs 本文件局部**二分：类型名 / func / **文件顶层** let·var 才全局可见；枚举 case 名、`@Published`/`@State` 实例属性、函数参数、for/catch/闭包/泛型变量只在本文件可见。裸标识符只在「本文件 local ∪ 跨文件 global」里才判已知 |
| 自检样例 | `lint-selftest/bad/` 新增跨文件场景（`SharedModel.swift` 的 `@Published notice` vs `Bad.swift` 裸用），自检从 3 处升到 **4 处** |

### 6.4 验证

- 检查器对**未修复版**精确命中 CI 的 3 处（26 / 63 / 77 行，行号与 xcodebuild 完全一致）；
  对修复版 **0 误报**（全仓库 106 文件）。
- 其余静态检查（swiftcheck / dups / yamlcheck）与 verify20–24 选择器镜像全部通过。

### 6.5 教训

「宁可漏报不可误报」不能以「全局集合」的方式实现——那会**系统性地漏掉整类 bug**。
正确的保守方向是「**缩小跨文件可见范围**」：只把真正跨文件可见的符号（类型、全局函数、
顶层常量）放进全局集合，其余一律按文件隔离。这样既不会误报（本文件的裸用仍认得），
也不会漏报（跨文件的同名误用会被精确捕获）。
