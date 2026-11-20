import Foundation

@main
struct TabStripTests {
    static func main() {
        let exact = TabStripMetrics(available: 156, count: 3)
        assert(exact.tabWidth == 50 && exact.viewport == 156 && !exact.overflows)
        let shrinking = TabStripMetrics(available: 155, count: 3)
        assert(shrinking.tabWidth < 50 && !shrinking.overflows && shrinking.viewport == 155)
        let compact = TabStripMetrics(available: 78, count: 3)
        assert(compact.tabWidth == 24 && compact.viewport == 78 && !compact.overflows)
        let slightOverflow = TabStripMetrics(available: 77, count: 3)
        assert(slightOverflow.tabWidth == 24 && slightOverflow.overflows && slightOverflow.viewport == 77)
        assert(!slightOverflow.canScrollLeft(at: 0))
        assert(slightOverflow.canScrollRight(at: 0))
        assert(slightOverflow.canScrollLeft(at: 1))
        assert(!slightOverflow.canScrollRight(at: 1))
        assert(!compact.canScrollLeft(at: 500) && !compact.canScrollRight(at: 500), "Stale offsets must not show arrows without overflow")
        let room = TabStripMetrics(available: 302, count: 4)
        assert(room.tabWidth == 73.25 && !room.overflows)
        assert(TabStripMetrics(available: 900, count: 2).tabWidth == 158)
        assert(!TabStripMetrics(available: 0, count: 0).overflows)

        let crowded = TabStripMetrics(available: 500, count: 60)
        assert(crowded.tabWidth == 24 && crowded.viewport == 500)
        assert(!crowded.canScrollRight(at: 1117))
        assert(crowded.canScrollLeft(at: 1117))
        assert(!crowded.canScrollLeft(at: -20))
        assert(crowded.targetIndex(from: 0, forward: true) == 17)
        assert(crowded.targetIndex(from: 371, forward: false) == 0)
        assert(crowded.targetIndex(from: 372, forward: true) == 30)
        assert(crowded.targetIndex(from: 3126, forward: true) == 59)
        assert(TabStripMetrics.groupWidth(preferred: 0, content: 180, available: 1000) == 180)
        assert(TabStripMetrics.groupWidth(preferred: 0, content: 800, available: 1000) == 270)
        assert(TabStripMetrics.groupWidth(preferred: 420, content: 180, available: 1000) == 420)
        assert(TabStripMetrics.groupWidth(preferred: 10, content: 180, available: 1000) == 48)
        assert(TabStripMetrics.groupWidth(preferred: 900, content: 800, available: 600) == 430)
        assert(TabStripMetrics.groupWidth(preferred: .nan, content: 180, available: 1000) == 180)
        print("Tab strip sizing, overflow, paging and group width checks passed.")
    }
}
