import SwiftUI

/// 板块管理（我的 → 设置 → 版块管理）。
///
/// 用户在首页展示哪些板块、按什么顺序展示，全部由这里决定：
/// - 上半区「首页展示的板块」：可上下移动排序、可移除。
/// - 下半区「可添加的板块」：点「添加」加入首页。
struct BoardManageView: View {
    @Environment(\.colorScheme) private var scheme

    @State private var selected: [Board]
    @State private var available: [Board]

    private struct Board: Identifiable, Hashable {
        let id: Int
        let name: String
    }

    init() {
        _selected = State(initialValue: [
            Board(id: 2, name: "Discovery"),
            Board(id: 6, name: "Buy & Sell 交易服务区"),
            Board(id: 7, name: "Geek Talks 奇客怪谈"),
        ])
        _available = State(initialValue: [
            Board(id: 9, name: "Smartphone"),
            Board(id: 22, name: "麦客爱苹果"),
            Board(id: 56, name: "iPhone/iPod/iPad"),
            Board(id: 60, name: "Android/Chrome/Google"),
            Board(id: 50, name: "DC,NB,MP3,Gadgets"),
        ])
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(selected.enumerated()), id: \.element.id) { index, board in
                    HStack {
                        Text(board.name)
                            .foregroundStyle(Color.appTextPrimary(scheme))
                        Spacer()
                        Button { moveUp(index) } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        Button { moveDown(index) } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == selected.count - 1)
                        Button { remove(board) } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("首页展示的板块（按顺序）")
            } footer: {
                Text("拖动上下箭头调整首页板块顺序。")
            }

            Section("可添加的板块") {
                ForEach(available) { board in
                    HStack {
                        Text(board.name)
                            .foregroundStyle(Color.appTextPrimary(scheme))
                        Spacer()
                        Button("添加") { add(board) }
                            .font(.subheadline)
                            .foregroundStyle(Color.appPrimary(scheme))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground(scheme))
        .navigationTitle("版块管理")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func moveUp(_ index: Int) {
        guard index > 0 else { return }
        selected.swapAt(index, index - 1)
    }

    private func moveDown(_ index: Int) {
        guard index < selected.count - 1 else { return }
        selected.swapAt(index, index + 1)
    }

    private func remove(_ board: Board) {
        selected.removeAll { $0.id == board.id }
        available.append(board)
    }

    private func add(_ board: Board) {
        available.removeAll { $0.id == board.id }
        selected.append(board)
    }
}
