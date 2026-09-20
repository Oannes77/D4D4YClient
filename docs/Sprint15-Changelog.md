# Sprint 15 Changelog（2026-09-20）

本轮不新增功能，处理两件事：**CI 截图链路从 0 张恢复** + **一处浅色下的可读性缺陷**。

---

## 一、0 张截图的根因（提交 01d52b0）

### 现象
Codemagic `Screenshots` workflow 连续两轮导出 **0 张 png**，Collect 步骤只打印：

```
Skipped export for The test runner encountered an error: no matching attachments
--- png 数量: 0 ---
!!! 本次 build 日志中的 error 摘要如下：   ← 下面是空的
```

`error:` 摘要为空 ⇒ **编译并没有失败**，这是与以往「0 张 = 编译失败」完全不同的一种情况。

### 根因
完整 build 日志的最后一行写着真因（不在 `error:` 里，所以前两轮都被误导）：

```
Testing failed:
	Test target D4D4YClientScreenshots encountered an error
	(The bundle identifier for D4D4YClient.app couldn't be read.
	 CFBundleIdentifier not found in Info.plist for application at path:
	 ".../Debug-iphonesimulator/D4D4YClient.app")
```

来自 Sprint 13 的后台刷新改造：为了声明 `UIBackgroundModes` / `BGTaskSchedulerPermittedIdentifiers`
这两个**数组类型**的键，改成了手写 `Support/Info.plist` + `GENERATE_INFOPLIST_FILE: NO`，
但漏掉了 `CFBundleIdentifier` 等基础键。

- `INFOPLIST_FILE` + `GENERATE_INFOPLIST_FILE: NO` 之后，**构建系统不再自动注入 CFBundle\* 键**；
- 缺 `CFBundleIdentifier` 时编译完全成功，但产物**没有身份证、装不进模拟器**；
- UI 测试连 App 都装不上 ⇒ 每个界面都失败 ⇒ 0 张截图；
- 同理，该构建在真机上也装不上，不只是截图问题。

> 记录：Sprint 12 之后收到的 12 张验收图属于 **Sprint 12**；Sprint 13 提交后直接进入 Sprint 14，
> **Sprint 13 从未被 CI 验证过**，所以这个缺陷一直藏到 Sprint 14 的截图轮才暴露。

### 修复
`Support/Info.plist` 补回标准键组（值一律用构建设置变量，勿写死）：
`CFBundleDevelopmentRegion` / `CFBundleDisplayName` / `CFBundleExecutable` / `CFBundleIdentifier` /
`CFBundleInfoDictionaryVersion` / `CFBundleName` / `CFBundlePackageType`(APPL) /
`CFBundleShortVersionString` / `CFBundleVersion` + `LSRequiresIPhoneOS`；
后台刷新需要的 `UIBackgroundModes` 与 `BGTaskSchedulerPermittedIdentifiers` 原样保留。
本地用 plist 解析器校验：文件合法、14 个键齐全。

### 顺带留下的排查手段（提交 9966521 / 98ff80d）
1. **Boot simulator 步骤先 `shutdown all` + `erase`**：清掉上一轮残留状态。
   （本轮验证下来不是这个原因，但保留作为常规卫生措施。）
2. **Build 步骤恒打印测试摘要**：`Test Case` / `Test Suite` / `Test runner` / `crashed` / `timed out` 等，
   不再只在 0 张时才输出。
3. **0 张时的诊断块扩充**：额外打印 runner/崩溃相关行 + build 日志最后 60 行。
4. **截图测试对未到前台的 App 重试一次并打印 state 值**
   （`0=unknown / 1=notRunning / 2=runningBackground / 3=runningForeground / 4=suspended`）。

> 结论/教训：**0 张截图的真因请先搜 build 日志尾部的 `Testing failed`**，而不是只看 `error:` 摘要。

---

## 二、浅色下输入框不可见（本轮唯一 UI 修改）

「我的 → 回帖占位符」的占位符输入框是 `List` 里的裸 `TextField`：
浅色下 List 行底色与页面同为白色，既无填充也无描边 ⇒ **看起来像一段静态文字，用户不知道可以改**
（暗色下因为有分组背景才勉强能看出是个框）。

按项目既有口径（与回复框输入区 `ReplyEditor` 一致）修复：
`appSurfaceSecondary` 填充 + `appBorder` 0.5pt 描边 + 圆角 10 + 内边距。

---

## 三、截图验收清单调整

- 本轮验收通过（移入 `confirmedTargets`，默认不再重复跑）：
  `myThreads` / `myFriends` / `myFollows` / `pushSettings`；
- 下一轮待验收（`targets`）：`replyPlaceholder`（因为输入框改了，需要重看亮暗两张）。
