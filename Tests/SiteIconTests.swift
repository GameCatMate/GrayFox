import AppKit
import Foundation
import Combine
import WebKit

@main
struct SiteIconTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let base = URL(string: CommandLine.arguments[1])!
        var finished = false
        Task { @MainActor in
            do {
                try await check(base)
                finished = true
            } catch {
                fatalError("Icon tests failed: \(error)")
            }
        }
        while !finished { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    @MainActor private static func check(_ base: URL) async throws {
        let legacy = try JSONDecoder().decode(Page.self, from: Data("{\"title\":\"Legacy\",\"url\":\"https://example.org/path\"}".utf8))
        assert(legacy.iconURL == nil)
        assert(SiteIcons.sources(for: legacy) == [URL(string: "https://example.org/favicon.ico")!])
        assert(SiteIcons.sources(for: Page(title: "File", url: URL(fileURLWithPath: "/tmp/icon"))).isEmpty)
        assert(SiteIcons.decode(Data("invalid".utf8)) == nil)

        let icons = SiteIcons(isPrivate: true)
        var updates = 0
        let observation = icons.objectWillChange.sink { updates += 1 }
        defer { withExtendedLifetime(observation) {} }
        let page = Page(title: "Restored tab", url: base.appending(path: "unopened-page"))
        let sources = SiteIcons.sources(for: page)
        async let first = icons.load(sources)
        async let duplicate = icons.load(sources)
        let loaded = await (first, duplicate)
        assert(loaded.0 != nil && loaded.0 === loaded.1)
        assert(icons.cached(sources) === loaded.0)
        assert(updates > 0, "All visible icons must observe cache updates")
        let (bytes, _) = try await URLSession.shared.data(from: base.appending(path: "counts"))
        let counts = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        assert((counts["requests"] as! [String: Int])["/favicon.ico"] == 1)
        assert(counts["cookies"] as? Bool == false)
        let rejected = await icons.load([base.appending(path: "large"), base.appending(path: "invalid")])
        assert(rejected == nil)
        let fallback = await icons.load([base.appending(path: "invalid")] + sources)
        assert(fallback === loaded.0)

        var mirror = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        mirror.host = "localhost"
        let alternate = mirror.url!
        let missing = Page(title: "Previously missing", url: alternate.appending(path: "one"))
        let shared = SiteIcons(isPrivate: true)
        let missingImage = await shared.load(SiteIcons.sources(for: missing))
        assert(missingImage == nil)
        let custom = alternate.appending(path: "site-icon.png")
        shared.remember(custom, for: alternate.appending(path: "two"))
        assert(shared.candidates(for: missing).first == custom)
        let recovered = await shared.load(shared.candidates(for: missing))
        assert(recovered != nil && shared.cached(shared.candidates(for: missing)) === recovered)
        let stale = Page(title: "Old icon", url: alternate.appending(path: "three"),
                         iconURL: alternate.appending(path: "old-icon.ico"))
        let updated = await shared.load(shared.candidates(for: stale))
        assert(updated === recovered)
        assert(shared.candidates(for: page) == SiteIcons.sources(for: page), "Origins must stay separate")

        let suite = "myBro.icons.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var state = BrowserData()
        state.tabs = [SavedTab(), SavedTab(page: page),
                      SavedTab(page: Page(title: "Known icon", url: base.appending(path: "known"),
                                          iconURL: base.appending(path: "site-icon.png")))]
        state.selected = 0
        defaults.set(try JSONEncoder().encode(state), forKey: "browser-state")
        let browser = Browser(defaults: defaults)
        let inactive = browser.tabs[1]
        assert(inactive.view == nil)
        assert(browser.siteIcons.candidates(for: page).first == base.appending(path: "site-icon.png"))
        let web = browser.prepare(browser.active!)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 420),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web
        web.load(URLRequest(url: base))
        let deadline = Date().addingTimeInterval(8)
        while browser.active?.saved.page?.iconURL == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        assert(browser.active?.saved.page?.iconURL == base.appending(path: "site-icon.png"))
        let discovered = await icons.load(SiteIcons.sources(for: browser.active!.saved.page!))
        assert(discovered != nil && discovered !== loaded.0)
        assert(inactive.view == nil)
        window.contentView = nil
        print("ICO/PNG decoding, request deduplication, cache, fallback, size limits, legacy tabs and WebKit icon discovery passed.")
    }
}
