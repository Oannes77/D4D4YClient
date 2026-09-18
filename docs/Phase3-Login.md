# D4D4YClient Phase 3 · 登录模块设计

> 状态：设计稿（待确认后实施）
> 前提：Discovery(fid=2) 与 Buy & Sell(fid=6) 需登录可见，游客不可见
> 平台：iOS 17+ / SwiftUI / SwiftData / async-await

---

## 0. 为什么登录是地基（不是可选项）

- Discovery（今日 3685 帖）与 Buy & Sell 全站最活跃，且**仅登录用户可见**。
- 游客身份请求 `index.php` 时，这两个分类在 HTML 中**整段不存在**。
- 新框架默认首页 = Discovery 主题列表 → **不登录，首页就是白屏**。

结论：登录从原 Phase 2 的「红线禁止项」变为**必须先做的地基模块**。

**红线更新（正式作废旧条款）**：允许实现登录、发帖、回帖、站内短信。
**保留边界**：仅走正常表单流程，**禁止绕过 Cloudflare / 验证码 / 权限**，禁止存储明文密码。

---

## 1. 已核实的协议细节（源码级）

来源：MIT 开源 Android 客户端 `webrules/4d4y` 实测实现，与用户确认一致。

| 环节 | 细节 |
|---|---|
| 取 formhash | 请求任意页面（如 `forumdisplay.php?fid=2`），正则 `name="formhash" value="([^"]*)"` |
| 登录接口 | `POST https://www.4d4y.com/forum/logging.php?action=login&loginsubmit=yes` |
| Content-Type | `application/x-www-form-urlencoded` |
| 表单字段 | `sid`、`formhash`、`loginfield=username`、`username`、`password`、`questionid`、`answer`、`loginsubmit=true` |
| **关键坑** | **answer 必须 GBK 编码**（iOS 侧用 `String.Encoding(rawValue: 2147485234)`，与现有 GB18030 处理同源） |
| 成功判定 | 响应体包含 **「欢迎您回来」** |
| 未登录判定 | 页面包含 **「您还未登录」** → 清 cookie → 回登录页 |
| 凭据 | 从 `Set-Cookie` 提取 cookie 串；iOS 存 **Keychain**，不进 SwiftData |
| 有效性粗判 | cookie 串长度 < 50 视为无效 |
| 有效期 | `cdb_cookietime=2592000`（30 天） |
| 必需请求头 | `cookie`、`referer: https://www.4d4y.com/forum/forumdisplay.php?fid=2`、`origin`、`upgrade-insecure-requests: 1`、桌面版 Chrome UA |

---

## 2. 模块结构

```
Core/Authentication/
├── AuthenticationState.swift      // 已有：guest / authenticated(UserSession)
├── UserSession.swift              // 已有：uid / username / loginTime
├── SessionManager.swift           // 已有壳：改造为真实会话管理
├── LoginService.swift             // 新增：formhash 抓取 + 登录 POST + 结果判定
├── KeychainStore.swift            // 新增：cookie 安全存取（Keychain）
└── SecurityQuestion.swift         // 新增：安全问题 questionid 枚举与答案编码

Features/Login/
├── LoginView.swift                // 新增：账号 / 密码 / 安全问题 / 答案
└── LoginViewModel.swift           // 新增：登录流程编排与错误态
```

**网络层改动（`Network/HTTPClient.swift`）**：
- 支持注入 cookie（登录后所有请求携带）
- 暴露响应 `Set-Cookie`，供登录与刷新使用
- 统一 GB18030 解码（已有）
- **统一掉线检测**：任意响应含「您还未登录」→ 通知 SessionManager 失效

---

## 3. 数据流

```
App 启动
 └─ SessionManager.restore()
     ├─ Keychain 读到有效 cookie → .authenticated → 首页加载 fid=2
     └─ 无/无效（长度<50）      → .guest        → 呈 LoginView

LoginView
 └─ ① GET forumdisplay.php?fid=2 → 解析 formhash
 └─ ② 用户输入 账号/密码/安全问题序号/答案
 └─ ③ POST logging.php（answer 用 GBK 编码）
     ├─ 响应含「欢迎您回来」 → 存 cookie 到 Keychain → .authenticated → 首页
     └─ 否则 → 展示「登录失败，请检查用户名、密码等」

运行期
 └─ 任意响应含「您还未登录」 → 清 Keychain cookie → .guest → 回登录页
```

---

## 4. 关键实现点

1. **GBK 答案编码**：`answer` 字段必须 GBK URL 编码，直接决定安全问题能否通过。
2. **Keychain 而非 SwiftData**：凭据禁止落 SwiftData（沿用原 Phase 2 约定）。
3. **掉线检测集中化**：在 HTTPClient 或 Repository 层统一判定，避免各页面重复。
4. **安全问题**：`questionid` 为下拉序号（0/1/2…），需从真实登录页抓取选项列表确认枚举值。
5. **不存明文密码**：仅在登录请求中使用，用完即弃。

---

## 5. 待真机 / 运行时验证项

| 项 | 说明 |
|---|---|
| 安全问题枚举 | `questionid` 各序号对应的问题文本，需抓真实登录页确认 |
| `sid` 是否必需 | Android 实现硬编码了 `sid=slxZ7x`，iOS 侧应先抓页面真实值 |
| Cloudflare 行为 | 登录 POST 是否触发质询（比公开页更严格，需实测） |
| cookie 结构 | 需确认哪些 cookie 项为会话必需（`cdb_sid` / `cdb_auth` 等） |

---

## 6. 验收标准

- 首次启动无 cookie → 自动进登录页。
- 正确账号密码（含安全问题）→ 登录成功 → 首页显示 Discovery(fid=2) 主题列表。
- 杀 App 重启 → cookie 从 Keychain 恢复 → 免登录直接进首页。
- cookie 失效 → 自动检测并回登录页，不白屏。
- 全程无明文密码存储，无验证码 / Cloudflare 绕过代码。
