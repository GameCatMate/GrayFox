import AppKit
import WebKit

@main
struct BrowserTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        testReordering()
        let browser = Browser(isPrivate: true)
        let original = browser.active!
        assert(original.view == nil)
        let suite = "myBro.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let window = Browser(defaults: defaults)
        let ungrouped = window.active!
        assert(window.createGroup("Работа"))
        window.setGroupTint(.purple, for: "Работа")
        assert(Browser(defaults: defaults).groupTint(for: "Работа") == .purple)
        assert(window.activeGroup == "Работа" && window.visibleTabs.count == 1)
        let first = window.active!
        let next = window.newTab()
        assert(next.saved.group == "Работа" && window.visibleTabs.count == 2)
        window.reorder(next, at: first)
        assert(window.visibleTabs.first === next)
        window.stepTab(1)
        assert(window.active === first)
        window.togglePin(first)
        assert(window.visibleTabs.first === first)
        window.selectGroup(nil)
        assert(window.active === ungrouped && window.visibleTabs.count == 1)
        window.selectGroup("Работа")
        window.select(next)
        window.selectGroup(nil)
        window.selectGroup("Работа")
        assert(window.active === next)
        window.selectGroup(nil)
        window.move(ungrouped, to: "Работа")
        assert(window.activeGroup == "Работа" && window.visibleTabs.count == 3)
        assert(window.createGroup("Личное", containing: next))
        assert(window.active === next && window.visibleTabs.count == 1)
        assert(!window.renameGroup("Личное", to: "Работа"))
        assert(window.renameGroup("Личное", to: "Чтение"))
        window.close(next)
        assert(window.activeGroup == "Чтение" && window.visibleTabs.isEmpty)
        window.selectGroup("Работа")
        window.select(ungrouped)
        window.selectGroup("Чтение")

        let restored = Browser(defaults: defaults)
        assert(restored.activeGroup == "Чтение" && restored.data.groups == ["Работа", "Чтение"])
        assert(restored.visibleTabs.isEmpty)
        restored.selectGroup("Работа")
        assert(restored.visibleTabs.count == 2 && restored.visibleTabs.first?.saved.pinned == true)
        assert(restored.active?.saved.pinned == false)
        restored.removeGroup("Работа")
        assert(restored.activeGroup == nil && restored.visibleTabs.count == 2)
        for tab in restored.visibleTabs { restored.close(tab) }
        assert(restored.tabs.isEmpty && restored.visibleTabs.isEmpty)
        let emptyWindow = Browser(defaults: defaults)
        assert(emptyWindow.tabs.isEmpty)
        emptyWindow.selectGroup("Чтение")
        assert(emptyWindow.visibleTabs.isEmpty)
        assert(emptyWindow.newTab().saved.group == "Чтение")
        let webTab = emptyWindow.active
        emptyWindow.show(.history)
        let history = emptyWindow.active
        assert(history !== webTab && history?.title == "История" && history?.saved.group == "Чтение")
        emptyWindow.show(.settings)
        assert(emptyWindow.active?.title == "Настройки" && emptyWindow.visibleTabs.count == 3)
        emptyWindow.show(.history)
        assert(emptyWindow.active === history && emptyWindow.visibleTabs.count == 3)
        assert(Browser(defaults: defaults).active?.saved.internalPage == .history)

        let sample = Page(title: "Example", url: URL(string: "https://example.org/")!)
        let now = Date()
        emptyWindow.recordVisit(sample, at: now.addingTimeInterval(-172_800))
        emptyWindow.recordVisit(sample, at: now.addingTimeInterval(-60))
        assert(emptyWindow.data.history.count == 2)
        emptyWindow.clearHistory(.day, now: now)
        assert(emptyWindow.data.history.count == 1)
        emptyWindow.deleteVisits([emptyWindow.data.history[0].id])
        assert(emptyWindow.data.history.isEmpty)
        let folder = emptyWindow.createBookmarkFolder("Work")!
        emptyWindow.saveBookmark(sample, folder: folder)
        assert(Browser(defaults: defaults).bookmarkFolder(containing: sample) == folder)
        let nestedFolder = emptyWindow.createBookmarkFolder("Projects", parent: folder)!
        emptyWindow.saveBookmark(sample, folder: nestedFolder)
        assert(emptyWindow.bookmarkFolder(containing: sample) == nestedFolder)
        assert(emptyWindow.renameBookmarkFolder(nestedFolder, to: "Active"))
        assert(Browser(defaults: defaults).bookmarkFolders.contains { $0.id == nestedFolder && $0.parentID == folder && $0.name == "Active" })
        emptyWindow.removeBookmarkFolder(nestedFolder)
        assert(emptyWindow.bookmarkFolder(containing: sample) == folder)
        emptyWindow.saveBookmark(sample, folder: nil)
        assert(emptyWindow.data.bookmarks == [sample])
        let previousFolder = Data(#"{"id":"A3CE7BBC-2EB1-40FE-A4E2-D4E3621B5C67","name":"Old","pages":[]}"#.utf8)
        assert(try! JSONDecoder().decode(BookmarkFolder.self, from: previousFolder).parentID == nil)
        let legacyHistory = try! JSONEncoder().encode([sample])
        let migrated = try! JSONDecoder().decode([HistoryVisit].self, from: legacyHistory)
        assert(migrated[0].visitedAt == nil && migrated[0].page == sample)
        let privateSession = PrivateBrowsingSession()
        let firstPrivateWindow = Browser(isPrivate: true, privateSession: privateSession)
        let secondPrivateWindow = Browser(isPrivate: true, privateSession: privateSession)
        firstPrivateWindow.beginPrivateSession()
        secondPrivateWindow.beginPrivateSession()
        let sharedStore = firstPrivateWindow.prepare(firstPrivateWindow.active!).configuration.websiteDataStore
        assert(secondPrivateWindow.prepare(secondPrivateWindow.active!).configuration.websiteDataStore === sharedStore)
        firstPrivateWindow.endPrivateSession()
        assert(secondPrivateWindow.prepare(secondPrivateWindow.active!).configuration.websiteDataStore === sharedStore)
        secondPrivateWindow.endPrivateSession()
        assert(firstPrivateWindow.prepare(firstPrivateWindow.active!).configuration.websiteDataStore !== sharedStore)
        firstPrivateWindow.recordVisit(sample, at: now)
        assert(firstPrivateWindow.data.history.isEmpty)
        firstPrivateWindow.endPrivateSession()

        let firstStore = browser.prepare(original).configuration.websiteDataStore
        assert(!firstStore.isPersistent)
        browser.endPrivateSession()
        assert(browser.tabs.count == 1 && browser.active !== original && browser.active?.view == nil)
        let secondStore = browser.prepare(browser.active!).configuration.websiteDataStore
        assert(secondStore !== firstStore && !secondStore.isPersistent)
        print("Tab, group, persistence and private session checks passed")

        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--download-fixture",
           let url = URL(string: CommandLine.arguments[2]) {
            verifyDownloadsAndCookies(at: url)
        }

        if CommandLine.arguments.count == 2, let url = URL(string: CommandLine.arguments[1]) {
            browser.open(url)
            let deadline = Date().addingTimeInterval(15)
            while browser.active?.title != "Stvor smoke test",
                  browser.active?.error == nil, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            guard browser.active?.title == "Stvor smoke test", browser.active?.saved.page?.url == url,
                  browser.data.history.isEmpty else {
                let tab = browser.active!
                fatalError(tab.error ?? "Expected \(url), got \(String(describing: tab.saved.page)). WebKit URL \(String(describing: tab.view?.url)), title \(String(describing: tab.view?.title)), loading \(String(describing: tab.view?.isLoading))")
            }
            print("WebKit navigation and private history checks passed")
        }
    }

    @MainActor
    private static func verifyDownloadsAndCookies(at url: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("mybro-download-probe-27a1.txt")
        let sentinel = Data("existing file".utf8)
        try! sentinel.write(to: original)
        let browser = Browser(isPrivate: true, downloadsDirectory: folder)
        browser.open(url)
        waitFor { browser.active?.title == "myBro Local Fixture" }
        let cookieStore = browser.active!.view!.configuration.websiteDataStore.httpCookieStore
        var hasFixtureCookie: Bool?
        cookieStore.getAllCookies { cookies in
            hasFixtureCookie = cookies.contains { $0.name == "mybro_fixture" }
        }
        waitFor { hasFixtureCookie == true }
        var checkedCutoff = false
        Task {
            await browser.clearCookies(.hour, now: .now.addingTimeInterval(7_200))
            let olderCookies = await cookieStore.allCookies()
            assert(olderCookies.contains { $0.name == "mybro_fixture" })
            checkedCutoff = true
            await browser.clearCookies(.hour)
            hasFixtureCookie = await cookieStore.allCookies().contains { $0.name == "mybro_fixture" }
        }
        waitFor { hasFixtureCookie == false }
        assert(checkedCutoff)

        let downloadURL = url.appendingPathComponent("download")
        let suite = "myBro.download-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let normalBrowser = Browser(defaults: defaults, downloadsDirectory: folder)
        normalBrowser.open(downloadURL)
        waitFor { normalBrowser.downloads.items.count == 1 }
        let interrupted = Downloads(defaults: defaults)
        guard case .failed("Загрузка прервана") = interrupted.items.first?.state else {
            fatalError("The in-progress download did not restore as interrupted")
        }
        normalBrowser.newTab()
        normalBrowser.open(downloadURL)
        waitFor { normalBrowser.downloads.items.count == 2 }
        waitFor {
            normalBrowser.downloads.items.contains { item in
                guard case let .downloading(progress) = item.state else { return false }
                return progress.fractionCompleted > 0 && progress.fractionCompleted < 1
            }
        }
        waitFor {
            normalBrowser.downloads.items.allSatisfy {
                if case .complete = $0.state { return true }
                return false
            }
        }
        let restored = Downloads(defaults: defaults)
        assert(restored.items.count == 2)
        assert(restored.items.allSatisfy { item in
            if case .complete = item.state { return true }
            return false
        })
        assert(try! Data(contentsOf: original) == sentinel)
        let payload = Data(String(repeating: "myBro download probe\n", count: 1024 * 64).utf8)
        for copy in 1...2 {
            let file = folder.appendingPathComponent("mybro-download-probe-27a1 (\(copy)).txt")
            assert(try! Data(contentsOf: file) == payload)
        }
        let listedFile = restored.items[0]
        assert(listedFile.sourceURL == downloadURL)
        let privateURL = URL(string: "https://me:secret@example.org/report.pdf?token=secret#page")!
        assert(DownloadItem.historySource(privateURL)?.absoluteString == "https://example.org/report.pdf")
        restored.removeFromHistory(listedFile.id)
        assert(restored.items.count == 1)
        assert(listedFile.localFile == listedFile.destination)
        try! FileManager.default.removeItem(at: listedFile.destination!)
        assert(listedFile.localFile == nil)
        print("WebKit cookie removal, download progress, history recovery and filename collision checks passed")
    }

    private static func waitFor(_ condition: () -> Bool, file: StaticString = #file, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(18)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        }
        assert(condition(), "Timed out waiting for WebKit", file: file, line: line)
    }

    @MainActor private static func testReordering() {
        let suite = "myBro.drag.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let browser = Browser(defaults: defaults)
        for name in ["One", "Two", "Three"] { browser.createGroup(name) }
        let selected = browser.active
        browser.setGroupTint(.purple, for: "One")
        browser.reorderGroup("One", at: "Three")
        assert(browser.data.groups == ["Two", "Three", "One"])
        browser.reorderGroup("One", at: "Two")
        assert(browser.data.groups == ["One", "Two", "Three"])
        browser.reorderGroup("One", at: "One")
        browser.reorderGroup("Missing", at: "Two")
        assert(browser.active === selected && browser.activeGroup == "Three")
        let restored = Browser(defaults: defaults)
        assert(restored.data.groups == browser.data.groups)
        assert(restored.groupTint(for: "One") == .purple)
        assert(restored.tabs.map { $0.saved.group } == browser.tabs.map { $0.saved.group })
        browser.selectGroup("Two")
        let first = browser.active!
        let middle = browser.newTab(SavedTab(group: "Two", internalPage: .history))
        let last = browser.newTab(SavedTab(group: "Two", internalPage: .settings))
        browser.reorder(first, at: last, persist: false)
        assert(browser.visibleTabs.map(\.id) == [middle.id, last.id, first.id])
        let beforeDrop = Browser(defaults: defaults)
        assert(beforeDrop.visibleTabs.map(\.saved.internalPage) == [nil, .history, .settings])
        assert(beforeDrop.data.selected != browser.tabs.firstIndex { $0 === browser.active })
        browser.saveTabOrder()
        assert(Browser(defaults: defaults).data.selected == browser.tabs.firstIndex { $0 === browser.active })
        browser.reorder(first, at: middle)
        assert(browser.visibleTabs.map(\.id) == [first.id, middle.id, last.id])
        let order = browser.tabs.map(\.id)
        browser.reorder(first, at: selected!)
        assert(browser.tabs.map(\.id) == order)
        assert(Browser(defaults: defaults).visibleTabs.count == 3)
    }
}
