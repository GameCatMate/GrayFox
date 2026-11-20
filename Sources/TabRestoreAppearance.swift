import SwiftUI

struct TabRestoreAppearance: ViewModifier {
    let restored: Bool
    let reduceMotion: Bool
    @State private var appeared = false

    func body(content: Content) -> some View {
        let entering = restored && !appeared && !reduceMotion
        content
            .opacity(entering ? 0 : 1)
            .offset(x: entering ? -4 : 0)
            .task(id: restored) {
                guard restored else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                var transaction = Transaction(animation: reduceMotion ? nil : .easeOut(duration: 0.18))
                transaction.disablesAnimations = reduceMotion
                withTransaction(transaction) { appeared = true }
            }
    }
}
