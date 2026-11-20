import AppKit
import WebKit

@main struct TabActionsTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let suite = "myBro.tab-actions-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let browser = Browser(defaults: defaults)
        let outside = browser.active!
        browser.createGroup("Work")
        let pinned = browser.active!
        browser.togglePin(pinned)
        let left = browser.newTab(SavedTab(group: "Work", internalPage: .history))
        let target = browser.newTab(SavedTab(group: "Work", internalPage: .settings))
        let right = browser.newTab(SavedTab(group: "Work", internalPage: .downloads))
        browser.select(left)
        assert(browser.tabsToClose(relativeTo: target, scope: .left).map(\.id) == [left.id])
        assert(browser.tabsToClose(relativeTo: target, scope: .right).map(\.id) == [right.id])
        assert(browser.tabsToClose(relativeTo: target, scope: .others).map(\.id) == [left.id, right.id])
        browser.closeTabs(relativeTo: target, scope: .left)
        assert(browser.active === target && browser.tabs.contains { $0 === outside })
        assert(browser.tabs.contains { $0 === pinned })
        browser.reopen()
        assert(browser.active?.saved.internalPage == .history)
        let copy = browser.duplicate(target)!
        assert(copy !== target && copy.saved.internalPage == .settings && copy.saved.group == "Work")
        assert(!copy.saved.pinned && browser.visibleTabs.firstIndex { $0 === copy } == browser.visibleTabs.firstIndex { $0 === target }! + 1)
        browser.closeTabs(relativeTo: target, scope: .others)
        assert(browser.visibleTabs.map(\.id) == [pinned.id, target.id])
        assert(browser.active === target)
        let duplicate = browser.duplicate(target)!
        assert(duplicate !== target && duplicate.saved.internalPage == .settings && duplicate.saved.group == "Work")
        assert(!duplicate.saved.pinned && browser.visibleTabs.last === duplicate)
        browser.close(duplicate)
        browser.reopen()
        assert(browser.active?.saved.internalPage == .settings)
        browser.close(browser.active!)
        browser.reloadAll()
        assert(browser.tabs.allSatisfy { $0.view == nil }, "Reload all must preserve lazy tabs")
        browser.toggleMute(target)
        assert(target.saved.muted == true)
        let restored = Browser(defaults: defaults)
        assert(restored.tabs.first { $0.saved.internalPage == .settings }?.saved.muted == true)
        browser.toggleMute(target)
        assert(target.saved.muted != true)
        let firstProbe = ReloadProbe(), secondProbe = ReloadProbe()
        outside.view = firstProbe
        target.view = secondProbe
        browser.reload(outside)
        assert(firstProbe.reloads == 1 && secondProbe.reloads == 0 && browser.active === target)
        browser.reloadAll()
        assert(firstProbe.reloads == 2 && secondProbe.reloads == 1)
        outside.view = nil
        target.view = nil
        let legacy = try JSONDecoder().decode(SavedTab.self, from: Data(#"{"pinned":false}"#.utf8))
        assert(legacy.muted == nil)

        let web = browser.prepare(target)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = web
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        web.loadHTMLString("<video id='video'></video><audio id='quiet' muted></audio><iframe srcdoc=\"<video id='nested'></video>\"></iframe>", baseURL: URL(string: "https://fixture.invalid"))
        try await wait(web, "document.getElementById('video') !== null && frames.length === 1 && frames[0].document.getElementById('nested') !== null")
        try await wait(web, "typeof __myBroSetAudioMuted === 'function'")
        _ = try await web.evaluateJavaScript("window.audioContext = new AudioContext(); audioContext.resume(); true")
        try await wait(web, "audioContext.state === 'running'")
        browser.toggleMute(target)
        try await wait(web, "audioContext.state === 'suspended'")
        _ = try await web.evaluateJavaScript("audioContext.resume(); true")
        try await wait(web, "audioContext.state === 'suspended'")
        try await wait(web, "video.muted && quiet.muted && frames[0].document.getElementById('nested').muted")
        _ = try await web.evaluateJavaScript("video.muted = false; const added = document.createElement('audio'); added.id = 'added'; document.body.append(added)")
        try await wait(web, "video.muted && document.getElementById('added').muted")
        browser.toggleMute(target)
        try await wait(web, "audioContext.state === 'running'")
        _ = try await web.evaluateJavaScript("audioContext.suspend(); true")
        try await wait(web, "audioContext.state === 'suspended'")
        browser.toggleMute(target)
        browser.toggleMute(target)
        try await wait(web, "audioContext.state === 'suspended'")
        _ = try await web.evaluateJavaScript("audioContext.close(); true")
        try await wait(web, "!video.muted && quiet.muted && !document.getElementById('added').muted && !frames[0].document.getElementById('nested').muted")
        browser.toggleMute(target)
        web.loadHTMLString("<video id='video'></video>", baseURL: URL(string: "https://fixture.invalid"))
        try await wait(web, "document.getElementById('video') !== null && video.muted")
        browser.toggleMute(target)
        try await wait(web, "!video.muted")
        print("Tab actions: pinned/group boundaries, relative close, reopen, duplicate, lazy reload, legacy state and media mute across frames/reloads passed.")
    }

    @MainActor static func wait(_ web: WKWebView, _ expression: String) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        print("WebKit diagnostic:", (try? await web.evaluateJavaScript("document.body?.outerHTML")) ?? "no document")
        do { print("Frame diagnostic:", (try await web.evaluateJavaScript("[frames.length, frames[0]?.document?.body?.outerHTML]")) ?? "no frames") }
        catch { print("Frame error:", error) }
        fatalError("Timed out: \(expression)")
    }
}

@MainActor private final class ReloadProbe: WKWebView {
    var reloads = 0
    override func reload() -> WKNavigation? { reloads += 1; return nil }
}
