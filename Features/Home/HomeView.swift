import SwiftUI
import SwiftData

/// 首页：常用板块 + 最近浏览 + 最近帖子。
///
/// UI 方向：
/// - 取消顶部 Banner，不做营销首页。
/// - 板块入口以纯文字列表为主，配合极简线性 SF Symbols。
/// - 三块数据全部来自本地 SwiftData，不触发网络。
struct HomeView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\PinnedForum.sortOrder, order: .forward)]) private var pinned: [PinnedForum]
    @Query(sort: [SortDescriptor(\ReadHistory.lastReadTime, order: .reverse)]) private var history: [ReadHistory]
    @Query(sort: [SortDescriptor(\VisitedForum.lastVisitedAt, order: .reverse)]) private var visited: [VisitedForum]
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if pinned.isEmpty {
                        placeholderText("还没有固定板块，去「板块」长按可固定")
                    } else {
                        ForEach(pinned) { forum in
                            NavigationLink {
                                ThreadListView(section: ForumSection(
                                    id: forum.fid,
                                    name: forum.name,
                                    isSubForum: false))
                            } label: {
                                Label(forum.name, systemImage: "pin")
                                    .foregroundStyle(Color.appTextPrimary(scheme))
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    PinnedForum.unpin(fid: forum.fid, context: modelContext)
                                } label: {
                                    Label("取消固定", systemImage: "pin.slash")
                                }
                            }
                        }
                    }
                } header: {
                    SectionHeader(title: "常用板块")
                }
                .listRowBackground(Color.appBackground(scheme))

                Section {
                    let recent = viewModel.limitedHistory(history, max: 10)
                    if recent.isEmpty {
                        placeholderText("还没有浏览记录")
                    } else {
                        ForEach(recent) { item in
                            NavigationLink {
                                ThreadDetailView(tid: item.tid, title: item.title)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .lineLimit(2)
                                        .foregroundStyle(Color.appTextPrimary(scheme))
                                    Text(item.lastReadTime, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(Color.appTextTertiary(scheme))
                                }
                            }
                        }
                    }
                } header: {
                    SectionHeader(title: "最近浏览")
                }
                .listRowBackground(Color.appBackground(scheme))

                Section {
                    if visited.isEmpty {
                        placeholderText("还没有访问过板块")
                    } else {
                        ForEach(visited.prefix(12)) { forum in
                            NavigationLink {
                                ThreadListView(section: ForumSection(
                                    id: forum.fid,
                                    name: forum.name,
                                    isSubForum: false))
                            } label: {
                                Label(forum.name, systemImage: "clock.arrow.circlepath")
                                    .foregroundStyle(Color.appTextPrimary(scheme))
                            }
                        }
                    }
                } header: {
                    SectionHeader(title: "最近访问板块")
                }
                .listRowBackground(Color.appBackground(scheme))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground(scheme))
            .navigationTitle("4D4Y")
        }
    }

    private func placeholderText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.appTextTertiary(scheme))
    }
}

// MARK: - SectionHeader

/// 论坛化首页分组标题：小号、低存在感的文字，不使用大写强调色。
private struct SectionHeader: View {
    let title: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(title)
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(Color.appTextSecondary(scheme))
            .textCase(nil)
    }
}
