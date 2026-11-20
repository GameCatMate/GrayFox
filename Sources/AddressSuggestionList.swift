import SwiftUI

enum AddressSuggestion: Equatable {
    case site(Page)
    case search(String)

    var isSearch: Bool {
        if case .search = self { return true }
        return false
    }
}

struct AddressSuggestionAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct SearchEngineIcon: View {
    let engine: SearchEngine
    var size: CGFloat = 16

    private static let icons: [SearchEngine: NSImage] = [
        (SearchEngine.google, "SearchGoogle"),
        (.duckDuckGo, "SearchDuckDuckGo"),
        (.bing, "SearchBing")
    ].reduce(into: [:]) { icons, asset in
        if let url = Bundle.main.url(forResource: asset.1, withExtension: "png") {
            icons[asset.0] = NSImage(contentsOf: url)
        }
    }

    var body: some View {
        Group {
            if let image = Self.icons[engine] {
                Image(nsImage: image).resizable().scaledToFit()
            } else if engine == .brave {
                Text("B").font(.caption.weight(.bold)).foregroundStyle(.orange)
            } else {
                Image(systemName: "magnifyingglass")
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .help(engine.rawValue)
    }
}

struct AddressSuggestionList: View {
    let suggestions: [AddressSuggestion]
    let selectedIndex: Int
    let maxHeight: CGFloat
    let query: String?
    let engine: SearchEngine
    let isOpen: (Page) -> Bool
    let choose: (AddressSuggestion) -> Void
    @State private var hoveredIndex: Int?

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(suggestions.indices, id: \.self) { index in
                        Button { choose(suggestions[index]) } label: {
                            row(suggestions[index])
                                .padding(.horizontal, 8)
                                .frame(height: 32)
                                .background(
                                    index == (hoveredIndex ?? selectedIndex) ? Color.accentColor.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering { hoveredIndex = index }
                            else if hoveredIndex == index { hoveredIndex = nil }
                        }
                        .accessibilityAddTraits(selectedIndex == index ? .isSelected : [])
                        .id(index)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: min(maxHeight, CGFloat(suggestions.count) * 32))
            .onChange(of: selectedIndex) { _, index in scroll.scrollTo(index) }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary) }
        .shadow(color: .black.opacity(0.24), radius: 10, y: 4)
        .accessibilityLabel("Подсказки")
    }

    private func row(_ suggestion: AddressSuggestion) -> some View {
        HStack(spacing: 8) {
            switch suggestion {
            case let .search(text):
                if text == query {
                    SearchEngineIcon(engine: engine)
                } else {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                }
                Text(text)
                if text == query {
                    Text("Поиск в \(engine.rawValue)").foregroundStyle(.secondary)
                }
            case let .site(page):
                Image(systemName: "globe").foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(page.title).layoutPriority(1)
                Text(page.url.absoluteString).foregroundStyle(Color.accentColor)
                if isOpen(page) {
                    Spacer(minLength: 0)
                    Text("Перейти на вкладку").font(.caption).foregroundStyle(.secondary)
                        .layoutPriority(1)
                }
            }
        }
        .font(.callout)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
