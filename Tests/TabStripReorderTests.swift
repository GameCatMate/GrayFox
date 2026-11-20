import Foundation
import CoreGraphics

@main
struct TabStripReorderTests {
    static func main() {
        let frames = ["A": CGRect(x: 10, y: 0, width: 50, height: 30),
                      "B": CGRect(x: 64, y: 0, width: 100, height: 30),
                      "C": CGRect(x: 168, y: 0, width: 80, height: 30)]
        let viewport = CGRect(x: 10, y: 0, width: 238, height: 36)
        var drag = TabStripReorder(item: "A", order: ["A", "B", "C"], frames: frames)!
        drag.update(translation: 120, location: CGPoint(x: 145, y: 15), origin: 10, spacing: 4, viewport: viewport)
        assert(drag.order == ["B", "A", "C"])
        assert(drag.offset(for: "A", origin: 10, spacing: 4, viewport: viewport) == 16)
        assert(drag.frame(for: "A", origin: 10, spacing: 4).minX + drag.offset(for: "A", origin: 10, spacing: 4, viewport: viewport) == 130)
        drag.update(translation: 200, location: CGPoint(x: 225, y: 15), origin: 10, spacing: 4, viewport: viewport)
        assert(drag.order == ["B", "C", "A"])
        assert(drag.frame(for: "A", origin: 10, spacing: 4).minX + drag.offset(for: "A", origin: 10, spacing: 4, viewport: viewport) == 198)
        drag.update(translation: 0, location: CGPoint(x: 35, y: 15), origin: 10, spacing: 4, viewport: viewport)
        assert(drag.order == ["A", "B", "C"])
        assert(drag.arranged(["A", "C", "D"]) == ["A", "C", "D"])
        assert(TabStripReorder(item: "Missing", order: ["A"], frames: frames) == nil)
        var wide = TabStripReorder(item: "B", order: ["A", "B", "C"], frames: frames)!
        wide.update(translation: 1000, location: CGPoint(x: 248, y: 15), origin: 10, spacing: 4, viewport: viewport)
        assert(wide.order == ["A", "C", "B"])
        wide.update(translation: -1000, location: CGPoint(x: 10, y: 15), origin: 10, spacing: 4, viewport: viewport)
        assert(wide.order == ["B", "A", "C"])
        assert(wide.scrollDirection(in: viewport) == -1)
        assert(wide.scrollTarget(origin: -100, spacing: 4, viewport: viewport, forward: false) != nil)
        print("Live item position, variable-width reordering, bounds, edge-scroll and closed-item filtering checks passed.")
    }
}
