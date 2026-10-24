import SwiftUI
import OrbitCore

private struct NotchToolBudgetKey: EnvironmentKey { static let defaultValue = 600.0 }
extension EnvironmentValues {
    var notchToolBudget: Double {
        get { self[NotchToolBudgetKey.self] }
        set { self[NotchToolBudgetKey.self] = newValue }
    }
}

struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Only the history viewport scrolls; its search and controls remain in place.
struct FittingHistory<Content: View>: View {
    let limit: Double
    @ViewBuilder var content: Content
    @State private var measured: CGFloat = 1
    var body: some View {
        ScrollView {
            content.frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height) })
        }.scrollIndicators(.never).frame(height: min(limit, measured))
            .onPreferenceChange(ContentHeightKey.self) { measured = $0 }
    }
}

/// Growing collections use pages, so controls never disappear below the screen.
struct NotchPagedList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let heightBudget: Double
    var maximumRows = 3
    var spacing: Double = 8
    @ViewBuilder var row: (Item) -> Row
    @State private var requestedPage = 0
    @State private var rowHeight = 110.0
    private var capacity: Int { max(1, min(maximumRows, Int((heightBudget - 36) / max(1, rowHeight + spacing)))) }
    private var page: SurfacePage { SurfacePage(itemCount: items.count, requestedIndex: requestedPage, capacity: capacity) }
    var body: some View {
        Group { if !items.isEmpty {
        VStack(spacing: spacing) {
            ForEach(Array(items[page.range])) { item in
                row(item).fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { proxy in Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height) })
            }
            if page.count > 1 {
                HStack(spacing: 10) {
                    Text("\(page.range.lowerBound + 1)–\(page.range.upperBound) of \(items.count)").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button { requestedPage = page.index - 1 } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(OrbitIconButtonStyle()).disabled(page.index == 0).accessibilityLabel("Previous items")
                    Button { requestedPage = page.index + 1 } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(OrbitIconButtonStyle()).disabled(page.index == page.count - 1).accessibilityLabel("Next items")
                }
            }
        }
        } }.onPreferenceChange(ContentHeightKey.self) { if $0 > 0 { rowHeight = max(rowHeight, $0) } }
            .onChange(of: page.index) { _, index in requestedPage = index }
    }
}
