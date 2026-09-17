# D4D4YClient — 4D4Y 第三方论坛客户端 PoC（第一阶段）

目标站点：https://www.4d4y.com/forum/ （Discuz! 7.2，GBK 编码，已套 Cloudflare）

**范围**：仅公开内容只读。论坛版块 → 主题列表 → 帖子详情。
不含登录 / 注册 / 回复 / 发帖 / 私信 / 通知，不存在任何绕过权限或验证码的代码。

## Xcode 工程生成

方式 A（XcodeGen，推荐）：

```bash
brew install xcodegen
cd D4D4YClient
xcodegen generate
open D4D4YClient.xcodeproj
```

方式 B（手动）：Xcode → File → New → Project → iOS App（SwiftUI，Interface Swift，
Minimum Deployment iOS 17.0），命名 `D4D4YClient`，然后把 `App / Models / Network /
Parsers / Repositories / Features / Shared` 六个目录拖入工程；
File → Add Package Dependencies 添加 `https://github.com/scinfu/SwiftSoup`（2.7.0+）。

## 运行前须知

- 首页版块列表取自页面内置的 `#silder_l` 侧边导航（`index.php` 被 Cloudflare
  质询稳定拦截，代码不做任何绕过，直接改用可达页面上的导航数据）。
- Debug 构建会把每次响应的原始 HTML 落盘到
  `tmp/4d4y-debug/`（Log.dumpHTMLIfNeeded），用于核对真实 DOM。
- Parser 每次解析都会通过 os.Logger 输出行数与缺失字段统计（category: parser）。

## 目录

```
App/          D4D4YApp.swift        应用入口 + RootView
Models/       Models.swift          ForumSection / ForumThread / Post / PageInfo / 解析结果
Network/      HTTPClient.swift      URLSession 封装（GET，预留 POST/Cookie/Header/Session）
Parsers/      ThreadListParser.swift    主题列表（tr:has(td.listcon)）
              ThreadDetailParser.swift  楼层（div.detail + li[id^='pid']）
              ForumMenuParser.swift     版块菜单（#silder_l）
              PaginationParser.swift    分页（strong.fade + input[onclick]）
Repositories/ ForumRepository.swift 网络层 + Parser 组装为 Model
Features/Home/      HomeView + HomeViewModel
Features/Forum/     ThreadListView + ThreadListViewModel
Features/Thread/    ThreadDetailView + ThreadDetailViewModel
Shared/       Log.swift / Loadable.swift / HTMLContentView.swift
```

## 已验证的真实 DOM 事实（PoC 依据）

| 项 | 结论 |
|---|---|
| 论坛程序 | Discuz! 7.2 + 定制 wap 模板（非 X3，结构与常见教程完全不同） |
| 编码 | charset=gbk，用 GB18030 解码 |
| 主题行 | `tr:has(td.listcon)`，标题 `a.title`（tid 在 href），作者 `p[0] > a[href*='space.php?uid=']`，回复数 `a.num` |
| 楼层 | 一楼 `div.detail`（`div.detailcon#pid…`），回复 `li[id^='pid']`（`div.replytop` = `N#` + 作者 + 时间，正文 `div.replycon`） |
| 分页 | `<strong class="fade">当前/总</strong>`；上一/下一页在 `input[onclick*='page=']` 的 onclick 相对 URL 里 |
| 每页条数 | 列表 75 行/页，帖子 50 楼/页 |
| 屏蔽楼层 | 无 `div.replycon`，只有 `div.locked`（“作者被禁止或删除”），按合法楼层处理 |

## 第一阶段明确不做

登录、注册、回复、发帖、私信、收藏、通知、上传附件、任何形式的权限/验证码处理。
