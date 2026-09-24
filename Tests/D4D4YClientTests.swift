import Foundation
import SwiftSoup
import XCTest

@testable import D4D4YClient

/// Parser Fixture Tests。
///
/// 全部 fixture 来自真实抓取并验证过的 4D4Y 页面（见 Tests/Fixtures/），
/// 仅用于测试；正式 App 不读取任何 fixture。
///
/// 固定流程（与线上一致）：raw Data → HTMLDecoder.decode → *Parser.parse。
final class D4D4YClientTests: XCTestCase {

    private func fixtureData(_ name: String) -> Data {
        let url = Bundle(for: D4D4YClientTests.self)
            .url(forResource: name, withExtension: "html")!
        return (try? Data(contentsOf: url))!
    }

    /// 与线上一致的 Decode 路径：GBK 页面经 HTMLDecoder 转为 String。
    private func decodedFixture(_ name: String) -> String {
        HTMLDecoder.decode(fixtureData(name))!
    }

    // MARK: - ThreadListParser

    func testThreadListParser_page1_count() throws {
        let html = decodedFixture("forumdisplay_fid14_page1")
        let page = try ThreadListParser.parse(html: html)
        XCTAssertEqual(page.threads.count, 75, "fid=14 第 1 页应为 75 条主题")
    }

    func testThreadListParser_page1_fields() throws {
        let html = decodedFixture("forumdisplay_fid14_page1")
        let page = try ThreadListParser.parse(html: html)

        let target = page.threads.first { $0.id == 269563 }
        XCTAssertNotNil(target, "应解析出样例 tid=269563")
        XCTAssertEqual(target?.title.isEmpty, false)
        XCTAssertEqual(target?.authorName, "rrambo")
        XCTAssertEqual(target?.authorID, 182853, "作者链接中的 uid 应被提取")
        XCTAssertNotNil(target?.replies, "回复数列存在")
    }

    func testThreadListParser_anonymousAuthorIDNil() throws {
        let html = decodedFixture("forumdisplay_fid14_page1")
        let page = try ThreadListParser.parse(html: html)
        // 匿名帖（作者 <p> 内无 uid 链接）authorID 必须为 nil，而非 0 或错误值。
        XCTAssertTrue(page.threads.contains { $0.authorID == nil },
                       "应存在至少一条匿名主题（authorID == nil）")
    }

    func testThreadListParser_page2_count() throws {
        let html = decodedFixture("forumdisplay_fid14_page2")
        let page = try ThreadListParser.parse(html: html)
        XCTAssertEqual(page.threads.count, 75, "fid=14 第 2 页应为 75 条主题")
    }

    // MARK: - PaginationParser（主题列表）

    func testPaginationParser_listPage1() throws {
        let doc = try SwiftSoup.parse(decodedFixture("forumdisplay_fid14_page1"))
        let info = try XCTUnwrap(PaginationParser.parse(document: doc))
        XCTAssertEqual(info.currentPage, 1)
        XCTAssertEqual(info.totalPages, 919)
        XCTAssertNil(info.previousPageURL, "第 1 页无上一页")
        XCTAssertEqual(info.nextPageURL, "forumdisplay.php?fid=14&page=2")
    }

    func testPaginationParser_listPage2() throws {
        let doc = try SwiftSoup.parse(decodedFixture("forumdisplay_fid14_page2"))
        let info = try XCTUnwrap(PaginationParser.parse(document: doc))
        XCTAssertEqual(info.currentPage, 2)
        XCTAssertEqual(info.totalPages, 919)
        XCTAssertEqual(info.previousPageURL, "forumdisplay.php?fid=14&page=1")
        XCTAssertEqual(info.nextPageURL, "forumdisplay.php?fid=14&page=3")
    }

    // MARK: - ThreadDetailParser

    func testThreadDetailParser_page1_firstPost() throws {
        let html = decodedFixture("viewthread_tid193033_page1")
        let page = try ThreadDetailParser.parse(html: html)

        XCTAssertEqual(page.posts.count, 50, "1 楼 + 49 回复 = 50")
        let first = try XCTUnwrap(page.posts.first)
        XCTAssertEqual(first.floor, 1)
        XCTAssertEqual(first.authorName, "EC")
        XCTAssertEqual(first.authorID, 1142)
        XCTAssertNotNil(first.createdAt, "发帖时间应解析成功")
        XCTAssertEqual(first.id, 1863080, "一楼应取 detailcon 的 id=pid1863080")
        XCTAssertTrue(page.title.hasPrefix("Hi-pda"))
        XCTAssertEqual(page.typeName, "心得技巧", "标题分类前缀应被提取")
    }

    func testThreadDetailParser_blockedPost() throws {
        let html = decodedFixture("viewthread_tid193033_page1")
        let page = try ThreadDetailParser.parse(html: html)

        let blocked = page.posts.filter { $0.isBlocked }
        XCTAssertEqual(blocked.count, 1, "应恰好 1 个被屏蔽楼层")
        XCTAssertEqual(blocked.first?.id, 2026287, "屏蔽楼 pid 仍应被正确提取")
        XCTAssertFalse(blocked.first?.htmlContent.isEmpty ?? true, "屏蔽楼按合法楼层处理，保留提示文本")
    }

    func testThreadDetailParser_page2() throws {
        let html = decodedFixture("viewthread_tid193033_page2")
        let page = try ThreadDetailParser.parse(html: html)
        XCTAssertEqual(page.posts.count, 50, "第 2 页 50 个回复楼（无一楼）")
        XCTAssertTrue(page.posts.allSatisfy { $0.floor != nil }, "回复楼楼层号应全部解析")
        XCTAssertEqual(page.pageInfo.currentPage, 2)
        XCTAssertEqual(page.pageInfo.totalPages, 6)
        XCTAssertNotNil(page.pageInfo.previousPageURL, "第 2 页应有上一页")
        XCTAssertNotNil(page.pageInfo.nextPageURL, "第 2 页应有下一页")
    }

    // MARK: - Sprint 18：PC 模板（客户端全局改用桌面 UA 之后的唯一模板）

    /// 列表页：PC 模板应有 75 条，且**有浏览量**（WAP 模板不输出这个字段）。
    func testThreadListParser_pcTemplate() throws {
        let html = decodedFixture("forumdisplay_fid14_page1_pc")
        let page = try ThreadListParser.parse(html: html)
        XCTAssertEqual(page.threads.count, 75, "PC 模板 fid=14 第 1 页应为 75 条主题")

        let target = try XCTUnwrap(page.threads.first { $0.id == 193033 })
        XCTAssertTrue(target.title.hasPrefix("Hi-pda"))
        XCTAssertEqual(target.authorName, "EC")
        XCTAssertEqual(target.authorID, 1142)
        XCTAssertEqual(target.typeName, "心得技巧")
        XCTAssertEqual(target.replies, 296)
        XCTAssertEqual(target.views, 673371, "浏览量是 PC 模板才有的字段（WAP 模板没有）")

        // 匿名主题的 authorID 仍必须是 nil，不能塌成 0。
        XCTAssertTrue(page.threads.contains { $0.authorID == nil },
                      "应存在至少一条匿名主题（authorID == nil）")
    }

    /// 分页：PC 模板每页 50 楼，页码链接带 `&sid=`，**必须剥掉**（我们始终带 Cookie）。
    func testPaginationParser_pcTemplate_listPage1() throws {
        let doc = try SwiftSoup.parse(decodedFixture("forumdisplay_fid14_page1_pc"))
        let info = try XCTUnwrap(PaginationParser.parse(document: doc))
        XCTAssertEqual(info.currentPage, 1)
        XCTAssertEqual(info.totalPages, 919)
        XCTAssertNil(info.previousPageURL, "第 1 页无上一页")
        XCTAssertEqual(info.nextPageURL, "forumdisplay.php?fid=14&page=2",
                       "PC 链接里的 &sid=… 应被剥掉")
    }

    /// 详情页：PC 模板同样 50 楼（含 1 个屏蔽楼），标题按 `[分类] 标题` 拆分。
    func testThreadDetailParser_pcTemplate() throws {
        let html = decodedFixture("viewthread_tid193033_page1_pc")
        let page = try ThreadDetailParser.parse(html: html)

        XCTAssertEqual(page.posts.count, 50, "1 楼 + 49 回复 = 50")
        let first = try XCTUnwrap(page.posts.first)
        XCTAssertEqual(first.floor, 1)
        XCTAssertEqual(first.authorName, "EC")
        XCTAssertEqual(first.authorID, 1142)
        XCTAssertEqual(first.id, 1863080)
        XCTAssertTrue(page.title.hasPrefix("Hi-pda"), "标题应已去掉 [分类] 前缀")
        XCTAssertEqual(page.typeName, "心得技巧", "方括号里的分类应被提取")

        XCTAssertEqual(page.posts.filter { $0.isBlocked }.count, 1, "应恰好 1 个被屏蔽楼层")
    }

    /// 首帖图片：PC 模板的**附件图真实地址在 `file` 属性上**（`src` 是占位图），
    /// 且位于 `td.t_msgfont` 之外的 `div.postattachlist` —— 两处都踩过才会 0 张图。
    func testThreadDetailParser_pcTemplate_attachmentImageAppended() throws {
        let html = decodedFixture("viewthread_tid332225_page1_pc")
        let page = try ThreadDetailParser.parse(html: html)
        let first = try XCTUnwrap(page.posts.first)
        XCTAssertTrue(first.htmlContent.contains("attachments/day_061102"),
                      "附件图的真实地址（file 属性）应被追加到楼层正文里")
    }

    /// 首图解析（PC 模板，附件型主题）：过滤后应保留全部内容图（外链图床 + 附件图）。
    func testThreadImageParser_pcTemplate_keepsExternalAndAttachmentImages() throws {
        let html = decodedFixture("viewthread_tid332225_page1_pc")
        let urls = ThreadImageParser.parseContentImageURLs(from: html)
        XCTAssertEqual(urls.count, 6, "4 张外链图床 + 2 张附件图")
        XCTAssertTrue(urls.contains { $0.absoluteString.contains("day_061102") },
                      "附件图应被识别为内容图")
        XCTAssertTrue(urls.contains { $0.host?.contains("eawan.com") ?? false },
                      "老帖的外链图床不要求同域，否则会被误过滤")
    }

    /// 权威接口地址必须**真的写在站点 PC 模板里** —— 这两个字符串是收藏与关注的唯一依据，
    /// 写错了会让「收藏 / 关注」全部落空，所以用真实夹具把它们钉住。
    func testAuthorityURLs_comeFromRealPCTemplate() throws {
        let html = decodedFixture("viewthread_tid193033_page1_pc")
        XCTAssertTrue(html.contains("my.php?item=favorites&tid=193033"),
                      "收藏地址来自站点 favoritewin 弹层原文")
        XCTAssertTrue(html.contains("my.php?item=attention&action=add&tid=193033"),
                      "关注地址来自站点 favoritewin 弹层原文（[关注此主题的新回复]）")

        XCTAssertEqual(FavoriteRepository.listPath, "my.php?item=favorites&type=thread")
        XCTAssertEqual(AttentionRepository.listPath, "my.php?item=attention")
    }

    /// 「关注」是**主题型**栏目（参数 tid），不是用户型 —— 归错类别会让列表一条都认不出。
    func testMySpaceKind_attentionIsTopicTypeNotUserList() {
        XCTAssertFalse(MySpaceKind.follows.isUserList, "关注的是主题，不是人")
        XCTAssertTrue(MySpaceKind.friends.isUserList, "只有好友是用户型列表")
        XCTAssertEqual(MySpaceKind.follows.fallbackItem, "attention")
        XCTAssertTrue(MySpaceKind.follows.hasExternalEntry,
                      "关注的入口只在帖子页 favoritewin 里，不能因 my.php 导航缺项就判「本站没有」")
    }

    /// P1-3：当真实 pid 缺失时，fallback id 必须非零、稳定、唯一（不塌成 0）。
    func testPostID_fallbackStableAndNonZero() throws {
        let html = """
        <ul><li id="pid"><div class="replytop">5#Someone/ 2020-1-1 00:00</div>\
        <div class="replycon">hello</div></li></ul>
        """
        let a = try ThreadDetailParser.parse(html: html)
        let b = try ThreadDetailParser.parse(html: html)
        let idA = try XCTUnwrap(a.posts.first?.id)
        XCTAssertNotEqual(idA, 0, "缺失 pid 不应塌成 0")
        XCTAssertEqual(idA, try XCTUnwrap(b.posts.first?.id), "同一内容两次解析 id 应稳定一致")
    }

    /// P1-3：跨页真实 pid 不应出现重复 id（Identifiable 稳定）。
    func testPostID_uniqueAcrossPages() throws {
        let p1 = try ThreadDetailParser.parse(html: decodedFixture("viewthread_tid193033_page1"))
        let p2 = try ThreadDetailParser.parse(html: decodedFixture("viewthread_tid193033_page2"))
        let ids = (p1.posts + p2.posts).map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "所有楼层 id 应唯一")
    }

    // MARK: - ForumMenuParser

    func testForumMenuParser() throws {
        let html = decodedFixture("forumdisplay_fid14_page1")
        let sections = try ForumMenuParser.parse(html: html)
        XCTAssertGreaterThan(sections.count, 0, "应能解析出版块")

        let geek = sections.first { $0.id == 7 }
        XCTAssertNotNil(geek, "应解析出 fid=7")
        XCTAssertTrue(geek?.name.contains("Geek Talks") ?? false, "名称应含 Geek Talks")

        let joggler = sections.first { $0.id == 62 }
        XCTAssertNotNil(joggler, "应解析出子版块 fid=62")
        XCTAssertTrue(joggler?.isSubForum ?? false, "fid=62 应被标记为子版块")
    }

    // MARK: - HTMLDecoder（P1-1 配套）

    func testHTMLDecoder_gbkForumPage() {
        let text = HTMLDecoder.decode(fixtureData("forumdisplay_fid14_page1"))
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("Hi-pda") ?? false, "GBK 页面应被正确解码出中文/内容")
    }

    func testHTMLDecoder_cloudflareUTF8() {
        let text = HTMLDecoder.decode(fixtureData("index_cloudflare"))
        XCTAssertNotNil(text, "UTF-8 质询页应解出字符串")
    }

    // MARK: - Cloudflare 检测（P0-2 配套）

    func testCloudflareDetection_positive() {
        let data = fixtureData("index_cloudflare")
        XCTAssertTrue(HTTPClient.looksLikeCloudflareChallenge(data),
                      "含 'Just a moment...' + challenges.cloudflare.com 的页面应识别为 CF 质询")
    }

    func testCloudflareDetection_negativeOnForumPage() {
        let data = fixtureData("forumdisplay_fid14_page1")
        XCTAssertFalse(HTTPClient.looksLikeCloudflareChallenge(data),
                       "正常论坛页不应误判为 CF 质询")
    }

    // MARK: - 分页 URL 校验（P1-2 配套）

    func testIsAllowedForumPath() {
        XCTAssertTrue(HTTPClient.isAllowedForumPath("forumdisplay.php?fid=14&page=2"))
        XCTAssertTrue(HTTPClient.isAllowedForumPath("viewthread.php?tid=193033&extra=&page=3"))
        XCTAssertFalse(HTTPClient.isAllowedForumPath("https://evil.com/x"), "跨域绝对 URL 应拒绝")
        XCTAssertFalse(HTTPClient.isAllowedForumPath("https://www.4d4y.com/other/x"),
                       "base 之外路径应拒绝")
        XCTAssertFalse(HTTPClient.isAllowedForumPath("../secret"), "路径逃逸应拒绝")
    }
}
