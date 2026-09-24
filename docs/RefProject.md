# 参考项目事实（webrules/4d4y）

> 用途：**本站（4d4y.com）第三方客户端的权威实现参考**。
> 本客户端（iOS）在模板选择、帖子解析、附件上传三处的做法与它不同，
> 且经查证**我们的做法是绕远路 / 有错的**。本文留档其确切协议，作为改造依据。
>
> 来源：`https://github.com/webrules/4d4y`（Android / Kotlin，MIT，最后提交 2025-02）
> 本地副本：`_ref/`（MainActivity.kt / ThreadActivity.kt / NewActivity.kt / LoginActivity.kt 等）

---

## 一、最根本的一条：它用桌面 UA，从第一天就走 PC 模板

`MainActivity.kt` / `ThreadActivity.kt` / `NewActivity.kt` / `LoginActivity.kt`
**四个文件里每一个请求**都带同一个 UA：

```
Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)
Chrome/132.0.0.0 Safari/537.36 Edg/132.0.0.0
```

并统一附带：

| Header | 值 |
|---|---|
| `referer` | `https://www.4d4y.com/forum/` |
| `origin` | `https://www.4d4y.com`（POST 时） |
| `upgrade-insecure-requests` | `1` |
| `accept-language` | `en-US,en;q=0.9,zh-CN;q=0.8,zh-TW;q=0.7,zh;q=0.6` |
| `cache-control` | `max-age=0` |

⇒ 它拿到的**始终是完整 PC 模板**，因此它的解析器全都建立在 PC 结构上。

**对比**：我们的 `HTTPClient` 全局用移动 Safari UA → 始终拿 `templates/wap/`（精简骨架）。
图片、附件、收藏/关注/分享入口、发帖页的 `#imgattachform` **都在 PC 模板里**，WAP 模板里没有或为空转。
详见 `docs/SiteFacts.md`。

---

## 二、列表页解析（PC 结构）

`MainActivity.extractLinks` —— 一次正则同时取 tid / 标题 / 作者：

```kotlin
"<tbody id=\"normalthread_(\\d+)\">[\\s\\S]*?<span id=\"thread_\\d+\"><a[^>]*>([^<]+)</a></span>[\\s\\S]*?<cite>\\s*<a[^>]*>([^<]+)</a>\\s*</cite>"
```

- 条目容器：`tbody#normalthread_<tid>`
- 标题：`span#thread_<tid> > a` 的文本
- 作者：`cite > a` 的文本
- 分页：`content.contains("class=\"next\"")`
- 「您还未登录」→ 清 cookie + 跳登录

⚠️ **它的列表是纯文字（标题+作者），没有首图。**
「支持图片查看」指的是**详情页**里看图。
⇒ 「列表首图预览」是本客户端**自己加的需求**，参考项目不提供这块的实现。

---

## 三、帖子详情解析（PC 结构）

`ThreadActivity.extractPosts`：

```kotlin
"(?s)<td class=\"postauthor\".*?<div class=\"postinfo\">.*?<a[^>]*?>(.*?)</a>.*?</div>.*?<td class=\"t_msgfont\" id=\"postmessage_(\\d+)\">(.*?)</td>"
```

- 作者：`td.postauthor` 内 `div.postinfo > a`
- 楼层正文：`td.t_msgfont[id=postmessage_<pid>]`
- 图片：从正文 HTML 用 `<img.*?src="(.*?)".*?>` 抽，**然后把这些 `<img>` 从正文里删掉**，
  正文交给 `HtmlCompat.fromHtml()` 渲染，图片单独用 `Glide` 加载成 `ImageView`
- 图片过滤（噪声）：`default/attachimg.gif`、`smilies/`、`common/back.gif`、`images/attachicons/`
- 附件块：先用 `<div class="t_attach".*?</div>` 整块剔除，避免混入正文

**要点**：在 PC 模板下，正文 `<img src>` 是**可直接使用的真实地址**（登录态下），
所以它只是简单抽 `src` 就能显示图片，不需要额外请求。

**夜间模式图片处理**（`ColorInversionTransformation.kt`）：
对图片做颜色反转（ColorMatrix `-1` 三通道 + `255` 偏移），
解决论坛图片普遍白底、夜间模式刺眼的问题。
（`isPredominantlyWhite` 判断写了但被注释掉，实际是**无条件反转**。）

---

## 四、附件上传：**两步协议**（与我们的实现不同，且我们的做法是错的）

### 步骤 1 —— 先上传文件，拿 `aid`

```
POST https://www.4d4y.com/forum/misc.php?action=swfupload&operation=upload&simple=1&type=image
Content-Type: multipart/form-data
```

| 字段 | 说明 |
|---|---|
| `uid` | 从发帖页 `form#imgattachform` 的 hidden 域解析 |
| `hash` | 同上 |
| `Filedata` | 文件二进制，**文件名用原始名**（含扩展名） |

**响应体**（纯文本，`|` 分隔）：

```
DISCUZUPLOAD|0|<aid>
```

判定：`parts[0] == "DISCUZUPLOAD" && parts[1] == "0"` → `parts[2]` 即附件 ID。

### 步骤 2 —— 再用**普通表单**提交帖子（GBK）

```
POST https://www.4d4y.com/forum/post.php?action=newthread&fid=<fid>&extra=&topicsubmit=yes
Content-Type: application/x-www-form-urlencoded   // FormBody，字符集 GBK
```

| 字段 | 来源 / 说明 |
|---|---|
| `formhash` | `form#postform` hidden |
| `posttime` | `form#postform` hidden |
| `wysiwyg` | hidden，缺省 `"1"` |
| `iconid` | hidden，缺省 `""` |
| `subject` | 标题 |
| `typeid` | 主题分类 |
| `message` | 正文 + **尾部追加** `\n[attachimg]<aid>[/attachimg]\n`（每张一个） |
| `tags` | 标签，可空 |
| `attention_add` | `"1"` ← **发帖即关注该帖**（「关注」入口在此） |
| `attachnew[<aid>][description]` | 每个 aid 一条，值 `""` |

成功率判定：看响应最终 URL（非错误页即成功）。

### ⚠️ 我们目前的实现是错的

`Repositories/PostRepository.swift` 现在把**文件和正文放在同一个 multipart 请求**里
（文件域名兜底 `attach[]`）—— 这是**凭 Discuz 通用文档猜的**，未经任何验证。
正确做法就是上面这套两步协议。

---

## 五、登录

```
POST https://www.4d4y.com/forum/logging.php?action=login&loginsubmit=yes
body: sid=<固定串>&formhash=<解析>&loginfield=username&username=<原样>
      &password=<原样>&questionid=<安全问题序号>&answer=<GBK 编码>&loginsubmit=true
```

- `answer` 先 `URLDecoder.decode(UTF-8)` 再 `URLEncoder.encode(GBK)`
- `questionid` 是**下拉框的序号**（不是文本）
- `formhash` 来自登录页 hidden 域

⇒ 与我们的实现基本一致（我们也做了 GBK 百分号编码），**无需改动**。
差异：它用了 `sid` 固定值和明文密码；我们走 MD5 + 运行时解析，更稳。

---

## 六、对我们的意义

| 维度 | 结论 |
|---|---|
| UA / 模板 | **应改为桌面 UA → PC 模板**。这是它生产可用（有真实用户）所依赖的基础。 |
| 解析器 | 只有**解析层**受影响；UI 层拿的是解析后的模型，**不用动**。 |
| 测试夹具 | `Tests/Fixtures/` 的 3 个页面文件要换成 PC 版（重抓即可）。 |
| 附件上传 | **必须按第四节重写**（swfupload 两步），现方案不可用。 |
| 列表首图 | 参考项目没有；PC 模板下正文图片可直接取，首图能力反而更容易做。 |
| 「关注」 | `attention_add` 出现在发帖表单里 ⇒ 该功能确实存在，与 `my.php?item=attention` 互相印证。 |

---

*本文由排查「帖子列表首图取不到」时发现，用于纠正此前基于 WAP 模板的一系列结论。*
