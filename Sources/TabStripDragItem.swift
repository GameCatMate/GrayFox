import SwiftUI

struct TabStripDragItem: ViewModifier {
    let offset: CGFloat
    let active: Bool
    let measure: (CGRect) -> Void

    func body(content: Content) -> some View {
        ZStack {
            content
                .offset(x: offset)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { measure($0) }
        .zIndex(active ? 1 : 0)
        .transaction { if active { $0.animation = nil } }
    }
}
