import Foundation

struct TabStripMetrics {
    static let spacing: CGFloat = 3
    static let controlWidth: CGFloat = 24
    static let controlGap: CGFloat = 6
    static let minimumWidth: CGFloat = 24
    private static let maximumWidth: CGFloat = 158
    private static let edgeTolerance: CGFloat = 0.5

    let available: CGFloat
    let count: Int

    private var gaps: CGFloat { CGFloat(max(0, count - 1)) * Self.spacing }
    private var contentWidth: CGFloat { CGFloat(count) * tabWidth + gaps }

    var overflows: Bool {
        count > 0 && CGFloat(count) * Self.minimumWidth + gaps > available
    }

    var tabWidth: CGFloat {
        let fittingWidth = (available - gaps) / CGFloat(max(1, count))
        return min(Self.maximumWidth, max(Self.minimumWidth, fittingWidth))
    }

    var viewport: CGFloat {
        min(contentWidth, max(0, available))
    }

    static let groupResizeHandleWidth: CGFloat = 8

    static func groupWidth(preferred: CGFloat, content: CGFloat, available: CGFloat) -> CGFloat {
        let reserved = minimumWidth + 4 * controlWidth + 7 * controlGap + groupResizeHandleWidth
        let maximum = max(48, available - reserved)
        let requested = preferred.isFinite && preferred > 0 ? preferred : min(270, content)
        return min(maximum, max(48, requested))
    }

    func canScrollLeft(at offset: CGFloat) -> Bool {
        overflows && offset > Self.edgeTolerance
    }

    func canScrollRight(at offset: CGFloat) -> Bool {
        guard overflows else { return false }
        return contentWidth - viewport - max(0, offset) > Self.edgeTolerance
    }

    func targetIndex(from offset: CGFloat, forward: Bool) -> Int {
        let stride = tabWidth + Self.spacing
        let leadingIndex = Int(max(0, offset + Self.edgeTolerance) / stride)
        let page = max(1, Int(viewport / stride) - 1)
        return min(max(0, count - 1), max(0, leadingIndex + (forward ? page : -page)))
    }
}
