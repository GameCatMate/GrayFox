import Foundation
import CoreGraphics

struct TabStripReorder<ID: Hashable>: Equatable {
    let item: ID
    let initialFrame: CGRect
    private let widths: [ID: CGFloat]
    var order: [ID]
    var translation: CGFloat = 0
    var location: CGPoint = .zero

    init?(item: ID, order: [ID], frames: [ID: CGRect]) {
        guard order.contains(item), let frame = frames[item], frame.width > 0 else { return nil }
        self.item = item
        self.order = order
        initialFrame = frame
        widths = frames.mapValues(\.width)
    }

    func arranged(_ current: [ID]) -> [ID] {
        let valid = Set(current)
        let known = Set(order)
        return order.filter { valid.contains($0) } + current.filter { !known.contains($0) }
    }

    func frame(for id: ID, origin: CGFloat, spacing: CGFloat) -> CGRect {
        var x = origin
        for candidate in order {
            let width = widths[candidate] ?? initialFrame.width
            if candidate == id { return CGRect(x: x, y: initialFrame.minY, width: width, height: initialFrame.height) }
            x += width + spacing
        }
        return .zero
    }

    private func position(in viewport: CGRect) -> CGFloat {
        min(max(viewport.minX, viewport.maxX - initialFrame.width),
            max(viewport.minX, initialFrame.minX + translation))
    }

    func offset(for id: ID, origin: CGFloat, spacing: CGFloat, viewport: CGRect) -> CGFloat {
        guard id == item else { return 0 }
        return position(in: viewport) - frame(for: item, origin: origin, spacing: spacing).minX
    }

    func scrollDirection(in viewport: CGRect) -> Int {
        guard viewport.contains(location) else { return 0 }
        if location.x < viewport.minX + 18 { return -1 }
        if location.x > viewport.maxX - 18 { return 1 }
        return 0
    }

    func scrollTarget(origin: CGFloat, spacing: CGFloat, viewport: CGRect, forward: Bool) -> ID? {
        if forward {
            return order.first { frame(for: $0, origin: origin, spacing: spacing).maxX > viewport.maxX + 1 }
        }
        return order.reversed().first { frame(for: $0, origin: origin, spacing: spacing).minX < viewport.minX - 1 }
    }

    mutating func update(translation: CGFloat, location: CGPoint, origin: CGFloat,
                         spacing: CGFloat, viewport: CGRect) {
        self.translation = translation
        self.location = location
        guard let from = order.firstIndex(of: item) else { return }
        let center = position(in: viewport) + initialFrame.width / 2
        let current = frame(for: item, origin: origin, spacing: spacing).midX
        var destination = from
        for (index, candidate) in order.enumerated() where candidate != item {
            let target = frame(for: candidate, origin: origin, spacing: spacing)
            let rightThreshold = target.maxX <= viewport.maxX
                ? min(target.midX, viewport.maxX - initialFrame.width / 2) : target.midX
            let leftThreshold = target.minX >= viewport.minX
                ? max(target.midX, viewport.minX + initialFrame.width / 2) : target.midX
            if center > current && index > from && center >= rightThreshold { destination = index }
            if center < current && index < from && center <= leftThreshold { destination = min(destination, index) }
        }
        if from != destination {
            order.remove(at: from)
            order.insert(item, at: destination)
        }
    }
}
