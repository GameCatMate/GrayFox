import AppKit
import WebKit

@main
struct BrowserSettingsTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let suite = "myBro.settings-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let example = Page(title: "Example", url: URL(string: "https://example.org/")!)
        var state = BrowserData()
        state.groups = ["Работа"]
        state.tabs = [SavedTab(group: "Работа", internalPage: .history)]
        state.selected = 0
        state.bookmarks = [example]
        defaults.set(try JSONEncoder().encode(state), forKey: "browser-state")

        assert(Browser(defaults: defaults).active?.saved.internalPage == .history)
        defaults.set(false, forKey: BrowserPreference.restoreTabs)
        let blank = Browser(defaults: defaults)
        assert(blank.tabs.count == 1 && blank.active?.saved.internalPage == nil)
        assert(blank.allBookmarks == [example] && blank.data.groups == ["Работа"])

        defaults.set(true, forKey: BrowserPreference.restoreTabs)
        defaults.set(true, forKey: BrowserPreference.extraStartTab)
        let restored = Browser(defaults: defaults)
        assert(restored.activeGroup == "Работа" && restored.tabs.count == 2)
        assert(restored.active?.saved.internalPage == nil)

        defaults.set(125, forKey: BrowserPreference.pageZoom)
        defaults.set(18, forKey: BrowserPreference.minimumFontSize)
        let web = restored.prepare(restored.active!)
        assert(web.pageZoom == 1.25 && web.configuration.preferences.minimumFontSize == 18)
        defaults.set(150, forKey: BrowserPreference.pageZoom)
        defaults.set(14, forKey: BrowserPreference.minimumFontSize)
        restored.updatePageZoom()
        restored.updateMinimumFont()
        assert(web.pageZoom == 1.5 && web.configuration.preferences.minimumFontSize == 14)

        let customFolder = FileManager.default.temporaryDirectory.appendingPathComponent("myBro-Downloads-fixture")
        defaults.set(customFolder.path, forKey: BrowserPreference.downloadsFolder)
        let regularFolder = try restored.downloads.destinationDirectory()
        assert(regularFolder.path == customFolder.path)
        let privateWindow = Browser(isPrivate: true, defaults: defaults)
        let privateFolder = try privateWindow.downloads.destinationDirectory()
        assert(privateFolder.path == customFolder.path)
        defaults.set("keep this note", forKey: "local-notes")
        restored.resetSettings()
        assert(defaults.string(forKey: BrowserPreference.downloadsFolder) == nil)
        assert(defaults.string(forKey: "local-notes") == "keep this note")
        assert(restored.allBookmarks == [example] && web.pageZoom == 1 && web.configuration.preferences.minimumFontSize == 0)
        print("Session restore, site zoom and font, downloads folder, and settings reset passed.")
    }
}
