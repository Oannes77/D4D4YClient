# Sprint 25（2026-09-29）：build #57 截图验收 + 修掉「两个界面名同一张图」

## 一、本轮产物出身（先验出身，再看图）

| 项 | 值 |
|---|---|
| workflow | `screenshots` |
| build | **#57** |
| commit | `db367d9` |
| 张数 | **26**（13 界面 × 浅色 / 深色） |
| 时间戳 | 2026-09-28 14:32（UTC）/ 22:32（本地），同一秒内全部产出 |
| manifest | 有（顶层数组，2 个测试方法各带 13 条 attachment） |

**结论：这是「0 张图」事故修复后的第一次有内容的产物**，覆盖了 Sprint 21–25 的全部改动，
不再是 `bda9994` 之前那种「绿的构建 + 空目录」。

## 二、自动体检（`analysis/checkartifacts.mjs`）

```
png 张数: 26  ·  结论: 无可疑图（未发现整屏纯色/黑屏）
```

判据用的是**亮度 1% / 99% 分位极差**（不是平均亮度）：

- 26 张极差区间 92–255，最低的两张是 94（`dark-myFollows`）与 102（`light-newPost`），
  离「整屏同色 = 没渲染」的阈值（< 12）很远；
- `dark-myFollows` 平均亮度仅 2.4、主色占比 99%，**如果按平均亮度判会被误杀成黑屏** ——
  它其实是一张只有两行条目的正常深色页（上一轮已踩过这个坑，这里复核判据本身有效）。

内容密度按「每行亮度偏离均值的行占比」排序，最低的 5 张是
`myFollows`(5%) / `savedThreads`(6%) / `newPost`(9%) / `replyPlaceholder`(11%) / `boardLoginGate`(12%)——
逐一肉眼核对后确认**均为正常空态或表单页，不是渲染失败**。

## 三、逐张人工复核（按界面分组）

### 3.1 登录门 `boardLoginGate`（Sprint 21 的核心验收点）✅

浅色 / 深色两张都拍到了完整链路：

```
🔒 该版块需要登录
对不起，您还未登录，无权访问该版块。
[ 登录 ]                       ← 紫色主按钮
游客只能浏览部分版块；登录后可访问全部版块。
重试
```

- **达成主线目标**：「无权访问」与「暂无主题」已严格分开 —— 受限版块（Buy & Sell 交易服务区）
  不再显示成空列表。
- 锚点 `board-notice-login` 命中的是**登录按钮本身**，按钮出现即证明识别逻辑走对了分支。
- 逐像素复核：紫色元素的**纵向分布**在两种主题下一致（10–15% 处的版块 chip、
  40–45% 处的锁图标 + 登录按钮、90–95% 处的 Tab 选中态），无缺件。
- 文案与 `SiteAlertParser` 从真实夹具解析的结果一致，**不是手写文案**。

### 3.2 首页 `home` ✅

版块 chips（Discovery / Buy & Sell 交易服务区 / Geek Talks …）、时间筛选条
（一天 / 两天 / 周 / 月 / 季 / 热门）、帖子卡片（作者徽章、缩略图、`36 回复`、`3,820 浏览`）齐备。
第 2 条是拉黑作者，显示 `-已拉黑- Discovery控` + 「取消拉黑」占位 —— 本地拉黑行为正确。

### 3.3 帖子详情 `thread` / `threadImages` / `threadAttachments` / `threadShareMenu` ✅

| 图 | 复核到的事实 |
|---|---|
| `thread` | 标题栏有铅笔编辑入口；正文含真实外链；楼层尾部有编辑标记 `[ Last edited by EC on 2005-10-19 at 22:32 ]`；署名 `EC 发表于 2004-7-22 00:44 #2`；底部 回复 / 转发 / 收藏 / 举报 四图标 |
| `threadImages` | 正文内嵌**真实站点图片**并已渲染完成（非加载占位、非转圈）—— Sprint 18 切桌面 UA / PC 模板的成果可见 |
| `threadAttachments` | 附件出口正常：`plumsip4fix-nbp拼音显示版.part1.rar 900 KB · 下载 421 次`、`part2.rar 38.84 KB · 下载 423 次`，右侧分享按钮；上方提示「附件 2 个 · 下载需论坛登录」；正文里另有内嵌附件 `NBPcn+Plum+Cab+exe.part10.rar (433.62 KB)`「下载次数: 450」 |
| `threadShareMenu` | 点开分享后「系统分享」/「分享给好友」两项正常弹出，背景内容可见 |

**零伪造检查**：列表行与详情页均**未出现**已删除的金色 `◇ 积分` 徽标 —— 与红线一致。

### 3.4 发帖与回帖 `newPost` / `replyPlaceholder` ✅

- `newPost`：发布到（Discovery 下拉）、标题（标注「可选，留空自动取正文首行」）、
  正文、底部「图片」「附件」入口、「发布时自动附带（与正文隔一空行）Peace&Love」提示齐备。
- `replyPlaceholder`：占位符输入、效果预览、**实际提交内容**演示（正文 + 空行 + 占位符），
  并明确「占位符不会出现在输入框里，只在提交时附加。只回一个占位符（不写正文）时，
  提交内容就是占位符本身。」右上角「恢复默认」。

### 3.5 我的 / 社交 `savedThreads` / `myFollows` / `userCard` / `reportChat` ✅

- `savedThreads`：真实收藏列表（`Discovery · Kepler` / `Discovery · Discovery控`）+ 黄色星标。
- `myFollows`：两条「有新回复」的主题，版面正常（非空态但也不是渲染失败）。
- `userCard`：`老橡树 / 键盘会老，手感永存。` + `UID 1024 / 分组 论坛元老 / 帖数 328 / 积分 9520`
  + 加好友 / 私信 / 搜帖 / 拉黑 四动作，浮层压在「我的」页之上。
- `reportChat`：收件人 `4D4Y`，底部预填举报报文，含真实链接
  `https://www.4d4y.com/forum/viewthread.php?tid=193033`，右侧「发送」**需用户自己点**。

### 3.6 浅深一致性 ✅

13 个界面的浅色 / 深色版本，文案、数据、图标位置、控件尺寸完全一致，仅配色不同 ——
主题切换没有丢内容或改布局。

## 四、发现并修掉的问题：`homeSearchCompose` 与 `home` 是同一张图 🔴

### 症状

`44401840-….png`（`-homeSearchCompose`）与 `202CD1EF-….png`（`-home`）
**MD5 完全相同**（1,270,021 字节，逐字节一致）。

两个界面名指向同一张图，意味着「首页搜索 + 发帖那一行」这一项**实际上从未被验收过** ——
只是没人注意到，因为图本身就是个正常的首页。

### 根因

`AppScreenshotTests.swift` 原来的动作顺序是：

```
waitForAnchor(...) → app.swipeDown() → scrollToElement → tapElement → settle → screenshot
```

两处问题叠加：

1. **`app.swipeDown()` 是慢速拖拽**（约 16px/步）。它让列表**真的向上滚**，
   而不是「拽过顶部后回弹」。`HomeView` 的展开条件是
   `onPreferenceChange(ScrollOffsetKey.self) { if y > 4, searchCollapsed { 展开 } }` ——
   慢速拖拽压根走不到 `y > 4` 这个分支。
2. 即使侥幸展开，**后面的 settle 停顿期间列表的惯性滚动又会把它钉回收起态**
   （`y < -4` 立即收起）。

另外 `homeSearchCompose` 也**不是** `ScreenshotScreen` 的枚举 case，
它只是 `Target.name`（附件名前缀），所以它启动的是 `-DemoScreen=home` ——
与 `home` 目标完全相同，进一步放大了「两个名字同一张图」的隐蔽性。

### 修复（`D4D4YClientScreenshots/AppScreenshotTests.swift`）

1. **新增 `pullDownToReveal(_:)`**：改用
   `XCUICoordinate.press(forDuration: 0.05, thenDragTo:)` —— 快速下拽 + 立即松手，
   松手后滚视图回弹到顶部时 `y > 4` 必然成立。用 `app` 自身的归一化坐标
   （0.5, 0.25 → 0.5, 0.75），因为展开前那一行高度为 0，抓不到也抓不准。
2. **把下拉挪到所有滚动 / 点击之后、紧贴截图**，中间不再插入任何会滚动列表的动作。
3. 归档 `Target.pullDown` 字段的语义：从「先下拉一次」改为「截图前最后一步做下拉回弹」。

### 遗留观察（本轮不改，记录备查）

`homeSearchCompose` 的 `waitElement` 仍是 `home-post-open`（只保证首页主题行出现），
不等于「搜索那一行一定展开了」。上述修复让展开**在机制上**成为可能，
但没有任何断言能保证它真的展开 —— 下次拿到截图时应当**用肉眼确认那一行在**，
而不是看到「图不是黑的」就签字。若再出现同图，下一步是给展开态加一个
独立 identifier 并把它作为 `waitElement`。

## 五、静态检查与回归

| 检查 | 结果 |
|---|---|
| `swiftcheck`（括号 / 引号平衡） | 0 个问题文件 |
| `dups`（顶层类型重名） | 175 个文件作用域符号无重名 |
| `swiftlint-lite`（标签 / OSLog / 未声明标识符 / 枚举缺 case / 冗余 try?） | **通过**，0 硬错误 |
| `lint-selftest.sh`（检查器自检） | 4 处故意错误全部命中 + 合法样例零误报 |
| `verify20`–`verify24`（选择器镜像） | 全过（21 / 14 / 19 / 11 断言） |
| `yamlcheck`（CI 配置） | `alpha-build` 4 步、`screenshots` 5 步，解析正常 |

**顺带修了检查器的一处漏网**：`swiftlint-lite` 的「已知系统符号」白名单缺 `CGVector`，
导致新写的 `pullDownToReveal` 被误报成「未声明标识符」（2 处）。
已把 `CGVector`、`XCUICoordinate` 补进白名单，重跑后 0 误报。
这正好又验证了那条老规矩：**检查器误报要查为什么，不能当噪声忽略** ——
这次确实是白名单不全，不是代码写错。

## 六、待用户

1. 夹具里的 `discuz_uid=19657` 与表单 hash 是否脱敏（当前保留真实值）。
2. 去 Codemagic 重跑一次 **Screenshots**，验证 `homeSearchCompose` 这次是否真的展开
   （拿到图先看 MD5 是否还与 `home` 相同，再看那一行在不在）。
3. Sprint 24 的「编辑自己的帖子」仍未编译验证 —— screenshots workflow 只编 App target，
   新增的 `EditPostRepository` / `EditPostView` 与单测要跑 **Alpha Build** 才算数。
