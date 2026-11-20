import AppKit
import WebKit

@main
struct BrowserZoomTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "myBro.zoom-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let browser = Browser(defaults: defaults)
        assert(!browser.changePageZoom(.increase))
        let site = browser.active!
        let web = browser.prepare(site)
        assert(browser.pageZoomPercent == 100)
        assert(browser.changePageZoom(.increase))
        assert(browser.pageZoomPercent == 110 && web.pageZoom == 1.1)

        browser.show(.downloads)
        assert(browser.pageZoomPercent == 100)
        assert(browser.changePageZoom(.decrease))
        assert(browser.changePageZoom(.decrease))
        assert(browser.pageZoomPercent == 80)
        for _ in 0..<10 { _ = browser.changePageZoom(.decrease) }
        assert(browser.pageZoomPercent == 30)
        assert(browser.changePageZoom(.reset))
        assert(browser.pageZoomPercent == 100)

        browser.select(site)
        assert(browser.pageZoomPercent == 110 && web.pageZoom == 1.1)
        defaults.set(125, forKey: BrowserPreference.pageZoom)
        browser.updatePageZoom()
        assert(browser.pageZoomPercent == 125 && web.pageZoom == 1.25)
        assert(browser.changePageZoom(.increase))
        assert(browser.pageZoomPercent == 135 && web.pageZoom == 1.35)
        for _ in 0..<30 { _ = browser.changePageZoom(.increase) }
        assert(browser.pageZoomPercent == 300 && web.pageZoom == 3)
        assert(browser.changePageZoom(.reset))
        assert(browser.pageZoomPercent == 125 && web.pageZoom == 1.25)
        print("Per-tab zoom, 10-point steps, internal-page zoom, bounds, and default reset passed.")
    }
}
