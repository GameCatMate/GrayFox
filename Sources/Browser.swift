import AppKit
import SwiftUI
import WebKit

enum InternalPage: String, Codable {
    case history
    case settings
    case bookmarks
    case downloads
    case passwords
    case profile
    case extensions

    var availableInPrivate: Bool { self == .settings || self == .downloads }

    var title: String {
        switch self {
        case .history: "История"
        case .settings: "Настройки"
        case .bookmarks: "Избранное"
        case .downloads: "Загрузки"
        case .passwords: "Пароли"
        case .profile: "Перенос профиля"
        case .extensions: "Расширения"
        }
    }
}

struct SavedTab: Codable {
    var page: Page?
    var group: String?
    var pinned = false
    var muted: Bool?
    var internalPage: InternalPage?
    var closedAt: Date?
    var closedIndex: Int?
    var localFile: URL?
}

struct BrowserData: Codable {
    var tabs: [SavedTab] = []
    var selected: Int?
    var emptyGroup: String?
    var groupSelections: [Int]?
    var groups: [String] = []
    var groupTints: [String: GroupTint]?
    var bookmarks: [Page] = []
    var bookmarkFolders: [BookmarkFolder]?
    var history: [HistoryVisit] = []
    var closed: [SavedTab] = []
}

@MainActor
final class PrivateBrowsingSession {
    static let shared = PrivateBrowsingSession()
    private var store: WKWebsiteDataStore?
    private var windows = 0

    func acquire() -> WKWebsiteDataStore {
        let sessionStore = store ?? .nonPersistent()
        store = sessionStore
        windows += 1
        return sessionStore
    }

    func release() {
        windows -= 1
        if windows == 0 { store = nil }
    }
}

@MainActor
final class Tab: Identifiable {
    let id = UUID()
    var saved: SavedTab
    var view: WKWebView?
    var titleObservation: NSKeyValueObservation?
    var error: String?
    var retryURL: URL?
    var pageZoomOverride: Int?

    init(_ saved: SavedTab) {
        self.saved = saved
    }

    var title: String {
        saved.internalPage?.title ?? saved.page?.title ?? saved.localFile?.lastPathComponent ?? "Новая вкладка"
    }
}

enum TabCloseScope {
    case others, left, right
}

enum PageZoomAction {
    case increase, decrease, reset
}

@MainActor
final class Browser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    private enum Selection: Equatable {
        case tab(UUID)
        case empty(String?)
    }

    @Published private(set) var tabs: [Tab]
    @Published private var selection: Selection
    @Published private(set) var data: BrowserData
    let isPrivate: Bool
    let siteIcons: SiteIcons
    let downloads: Downloads
    let passwordVault: PasswordVault
    @Published private(set) var reopenedTabID: UUID?
    @Published var pendingLogin: SavedLogin?
    @Published var passwordError: String?
    @Published var migrationStatus: String?

    var passwordAutofill: Bool { defaults.object(forKey: PasswordForms.autofillKey) as? Bool ?? true }
    private let defaults: UserDefaults
    private let privateSession: PrivateBrowsingSession?
    private var privateStore: WKWebsiteDataStore?
    private var groupSelections: [String?: UUID] = [:]

    init(isPrivate: Bool = false, defaults: UserDefaults = .standard, downloadsDirectory: URL? = nil,
         privateSession: PrivateBrowsingSession? = nil, passwordVault: PasswordVault = PasswordVault()) {
        self.isPrivate = isPrivate
        siteIcons = SiteIcons(isPrivate: isPrivate)
        self.defaults = defaults
        self.passwordVault = passwordVault
        downloads = Downloads(directory: downloadsDirectory, defaults: isPrivate ? nil : defaults, preferences: defaults)
        self.privateSession = privateSession
        let restored = isPrivate ? nil : defaults.data(forKey: "browser-state")
            .flatMap { try? JSONDecoder().decode(BrowserData.self, from: $0) }
        var state = restored ?? BrowserData()
        let restoreTabs = BrowserPreference.enabled(defaults, BrowserPreference.restoreTabs)
        if !restoreTabs {
            state.tabs = []
            state.selected = nil
            state.emptyGroup = nil
            state.groupSelections = nil
        }
        if restoreTabs && !state.tabs.isEmpty && defaults.bool(forKey: BrowserPreference.extraStartTab) {
            let group = state.selected.flatMap { state.tabs.indices.contains($0) ? state.tabs[$0].group : nil }
                ?? state.emptyGroup
            state.tabs.append(SavedTab(group: group))
            state.selected = state.tabs.count - 1
        }
        data = state
        let startsBlank = restored == nil || !restoreTabs
        let initialTabs = startsBlank ? [Tab(SavedTab())] : state.tabs.map(Tab.init)
        tabs = initialTabs
        if let first = initialTabs.first, let index = startsBlank ? 0 : state.selected {
            selection = .tab(initialTabs.indices.contains(index) ? initialTabs[index].id : first.id)
        } else {
            let group = state.emptyGroup.flatMap { state.groups.contains($0) ? $0 : nil }
            selection = .empty(group)
        }
        super.init()
        for page in state.tabs.compactMap(\.page) {
            if let iconURL = page.iconURL { siteIcons.remember(iconURL, for: page.url) }
        }
        for index in state.groupSelections ?? [] where tabs.indices.contains(index) {
            let tab = tabs[index]
            groupSelections[tab.saved.group] = tab.id
        }
        if let activeID { groupSelections[activeGroup] = activeID }
    }

    private var store: WKWebsiteDataStore {
        guard isPrivate else { return .default() }
        if let privateStore { return privateStore }
        let newStore = privateSession?.acquire() ?? WKWebsiteDataStore.nonPersistent()
        privateStore = newStore
        return newStore
    }

    func beginPrivateSession() {
        if isPrivate { _ = store }
    }

    var activeID: UUID? {
        if case let .tab(id) = selection { return id }
        return nil
    }

    var active: Tab? { tabs.first { $0.id == activeID } }

    var activeGroup: String? {
        if case let .empty(group) = selection { return group }
        return active?.saved.group
    }

    var visibleTabs: [Tab] {
        let groupTabs = tabs.filter { $0.saved.group == activeGroup }
        return groupTabs.filter { $0.saved.pinned } + groupTabs.filter { !$0.saved.pinned }
    }

    private func save() {
        if let activeID { groupSelections[activeGroup] = activeID }
        guard !isPrivate else { return }
        data.tabs = tabs.map(\.saved)
        data.selected = tabs.firstIndex { $0.id == activeID }
        data.emptyGroup = data.selected == nil ? activeGroup : nil
        data.groupSelections = tabs.indices.filter { index in
            let tab = tabs[index]
            return groupSelections[tab.saved.group] == tab.id
        }
        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: "browser-state")
        }
    }

    @discardableResult
    func prepare(_ tab: Tab, configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        if let web = tab.view { return web }
        let config = configuration ?? WKWebViewConfiguration()
        if configuration == nil {
            config.websiteDataStore = store
            if !isPrivate { PasswordForms.install(in: config.userContentController, for: self) }
        }
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.minimumFontSize = BrowserPreference.minimumFont(in: defaults)
        TabAudio.install(in: config.userContentController, muted: tab.saved.muted == true)
        let web = WKWebView(frame: .zero, configuration: config)
        web.pageZoom = tab.pageZoomOverride.map { CGFloat($0) / 100 } ?? defaultPageZoom
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.isInspectable = true
        tab.view = web
        tab.titleObservation = web.observe(\.title, options: [.new]) { [weak self] observed, _ in
            Task { @MainActor [weak self, weak observed] in
                guard let observed else { return }
                self?.updateTitle(observed)
            }
        }
        if let file = tab.saved.localFile, file.isFileURL {
            web.loadFileURL(file, allowingReadAccessTo: file)
        } else if let page = tab.saved.page {
            web.load(URLRequest(url: page.url))
        }
        return web
    }

    @discardableResult
    func newTab() -> Tab {
        newTab(SavedTab(group: activeGroup))
    }

    @discardableResult
    func newTab(_ saved: SavedTab, configuration: WKWebViewConfiguration? = nil, at index: Int? = nil) -> Tab {
        let tab = Tab(saved)
        if let page = saved.page, let iconURL = page.iconURL {
            siteIcons.remember(iconURL, for: page.url)
        }
        tabs.insert(tab, at: min(tabs.count, max(0, index ?? tabs.count)))
        if configuration != nil || saved.page != nil || saved.localFile != nil { prepare(tab, configuration: configuration) }
        select(tab)
        return tab
    }

    func select(_ tab: Tab) {
        reopenedTabID = nil
        if tab.saved.page != nil || tab.saved.localFile != nil { prepare(tab) }
        selection = .tab(tab.id)
        if !isPrivate, let web = tab.view { PasswordForms.refresh(in: web) }
        save()
    }

    func stepTab(_ offset: Int) {
        let visible = visibleTabs
        guard let index = visible.firstIndex(where: { $0.id == activeID }) else { return }
        select(visible[(index + offset + visible.count) % visible.count])
    }

    func selectGroup(_ group: String?) {
        if let group, !data.groups.contains(group) { return }
        let members = tabs.filter { $0.saved.group == group }
        if let tab = members.first(where: { $0.id == groupSelections[group] }) ?? members.first {
            select(tab)
        } else {
            selection = .empty(group)
            save()
        }
    }

    func close(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        var saved = tab.saved
        saved.closedAt = .now
        saved.closedIndex = index
        data.closed.append(saved)
        data.closed = Array(data.closed.suffix(25))
        let visible = visibleTabs
        tabs.remove(at: index)
        if tab.id == activeID {
            if let position = visible.firstIndex(where: { $0.id == tab.id }), visible.count > 1 {
                select(visible[position > 0 ? position - 1 : 1])
                return
            }
            selection = .empty(tab.saved.group)
        }
        save()
    }

    func reopen() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            guard var saved = data.closed.popLast() else { return }
            let index = saved.closedIndex
            saved.closedAt = nil
            saved.closedIndex = nil
            reopenedTabID = newTab(saved, at: index).id
        }
    }

    @discardableResult
    func duplicate(_ tab: Tab) -> Tab? {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return nil }
        var saved = tab.saved
        saved.pinned = false
        saved.closedAt = nil
        saved.closedIndex = nil
        return newTab(saved, at: index + 1)
    }

    func tabsToClose(relativeTo tab: Tab, scope: TabCloseScope) -> [Tab] {
        let visible = visibleTabs
        guard let index = visible.firstIndex(where: { $0 === tab }) else { return [] }
        return visible.enumerated().compactMap { offset, item in
            guard item !== tab, !item.saved.pinned else { return nil }
            switch scope {
            case .others: return item
            case .left: return offset < index ? item : nil
            case .right: return offset > index ? item : nil
            }
        }
    }

    func closeTabs(relativeTo tab: Tab, scope: TabCloseScope) {
        let closing = tabsToClose(relativeTo: tab, scope: scope)
        if closing.contains(where: { $0.id == activeID }) { select(tab) }
        for item in closing.reversed() { close(item) }
    }

    func toggleMute(_ tab: Tab) {
        guard tabs.contains(where: { $0 === tab }) else { return }
        tab.saved.muted = tab.saved.muted == true ? nil : true
        if let web = tab.view { TabAudio.update(web, muted: tab.saved.muted == true) }
        objectWillChange.send()
        save()
    }

    func togglePin(_ tab: Tab) {
        tab.saved.pinned.toggle()
        objectWillChange.send()
        save()
    }

    func move(_ tab: Tab, to group: String?) {
        let previous = tab.saved.group
        if previous != group, groupSelections[previous] == tab.id {
            groupSelections.removeValue(forKey: previous)
        }
        tab.saved.group = group
        objectWillChange.send()
        save()
    }

    func reorder(_ tab: Tab, at target: Tab, persist: Bool = true) {
        guard tab !== target, tab.saved.group == target.saved.group,
              let from = tabs.firstIndex(where: { $0 === tab }),
              let to = tabs.firstIndex(where: { $0 === target }) else { return }
        tab.saved.pinned = target.saved.pinned
        tabs.remove(at: from)
        tabs.insert(tab, at: to)
        if persist { save() }
        else { objectWillChange.send() }
    }

    func saveTabOrder() { save() }

    func reorderGroup(_ group: String, at target: String) {
        guard group != target,
              let from = data.groups.firstIndex(of: group),
              let to = data.groups.firstIndex(of: target) else { return }
        data.groups.remove(at: from)
        data.groups.insert(group, at: to)
        save()
    }

    @discardableResult
    func createGroup(_ name: String, containing tab: Tab? = nil) -> Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !data.groups.contains(cleaned) else { return false }
        data.groups.append(cleaned)
        if let tab {
            move(tab, to: cleaned)
            select(tab)
        } else {
            newTab(SavedTab(group: cleaned))
        }
        return true
    }

    @discardableResult
    func renameGroup(_ oldName: String, to newName: String) -> Bool {
        let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned == oldName { return true }
        guard !cleaned.isEmpty, !data.groups.contains(cleaned),
              let index = data.groups.firstIndex(of: oldName) else { return false }
        data.groups[index] = cleaned
        if let tint = data.groupTints?.removeValue(forKey: oldName) {
            data.groupTints?[cleaned] = tint
        }
        updateMembership(oldName, to: cleaned)
        return true
    }

    func removeGroup(_ group: String) {
        data.groups.removeAll { $0 == group }
        data.groupTints?.removeValue(forKey: group)
        updateMembership(group, to: nil)
    }

    func groupTint(for group: String) -> GroupTint {
        data.groupTints?[group] ?? .blue
    }

    func setGroupTint(_ tint: GroupTint, for group: String) {
        guard data.groups.contains(group) else { return }
        var tints = data.groupTints ?? [:]
        tints[group] = tint
        data.groupTints = tints
        save()
    }

    private func updateMembership(_ group: String, to replacement: String?) {
        if selection == .empty(group) { selection = .empty(replacement) }
        if let selected = groupSelections.removeValue(forKey: group), let replacement {
            groupSelections[replacement] = selected
        }
        for tab in tabs where tab.saved.group == group { tab.saved.group = replacement }
        for index in data.closed.indices where data.closed[index].group == group {
            data.closed[index].group = replacement
        }
        save()
    }

    func open(_ url: URL) {
        guard Address.isWeb(url) else { return }
        let tab = active ?? newTab()
        tab.saved.internalPage = nil
        let web = prepare(tab)
        tab.error = nil
        tab.retryURL = url
        web.load(URLRequest(url: url))
        objectWillChange.send()
    }

    func open(_ page: Page) { open(page.url) }

    func openExternal(_ url: URL) {
        guard !isPrivate, Address.isWeb(url) else { return }
        if defaults.bool(forKey: BrowserPreference.reuseExternalTab),
           let existing = tabs.first(where: { $0.saved.page?.url == url }) {
            select(existing)
        } else if active?.saved.page == nil, active?.saved.internalPage == nil, active?.view == nil {
            open(url)
        } else {
            _ = newTab(SavedTab(page: Page(title: url.host ?? url.absoluteString, url: url), group: activeGroup))
        }
    }

    var defaultPageZoom: CGFloat { CGFloat(BrowserPreference.pageZoom(in: defaults)) }

    var defaultPageZoomPercent: Int { Int((defaultPageZoom * 100).rounded()) }

    var pageZoomPercent: Int { active?.pageZoomOverride ?? defaultPageZoomPercent }

    var canZoomPage: Bool {
        guard let tab = active, tab.error == nil else { return false }
        return tab.view != nil || tab.saved.internalPage != nil
    }

    @discardableResult
    func changePageZoom(_ action: PageZoomAction) -> Bool {
        guard canZoomPage, let tab = active else { return false }
        let next: Int
        switch action {
        case .increase: next = min(300, pageZoomPercent + 10)
        case .decrease: next = max(30, pageZoomPercent - 10)
        case .reset: next = defaultPageZoomPercent
        }
        objectWillChange.send()
        tab.pageZoomOverride = next == defaultPageZoomPercent ? nil : next
        tab.view?.pageZoom = CGFloat(next) / 100
        return true
    }

    func updatePageZoom() {
        objectWillChange.send()
        for tab in tabs {
            tab.pageZoomOverride = nil
            tab.view?.pageZoom = defaultPageZoom
        }
    }

    func updateMinimumFont() {
        let size = BrowserPreference.minimumFont(in: defaults)
        for tab in tabs { tab.view?.configuration.preferences.minimumFontSize = size }
    }

    func show(_ page: InternalPage) {
        guard !isPrivate || page.availableInPrivate else { return }
        if let tab = visibleTabs.first(where: { $0.saved.internalPage == page }) {
            select(tab)
        } else {
            newTab(SavedTab(group: activeGroup, internalPage: page))
        }
    }

    func reload() {
        if let active { reload(active) }
    }

    func reload(_ tab: Tab) {
        guard tabs.contains(where: { $0 === tab }) else { return }
        if let url = tab.retryURL, tab.error != nil {
            tab.error = nil
            prepare(tab).load(URLRequest(url: url))
            objectWillChange.send()
        } else {
            tab.view?.reload()
        }
    }

    func reloadAll() {
        for tab in tabs where tab.view != nil { reload(tab) }
    }

    func endPrivateSession() {
        guard isPrivate else { return }
        for tab in tabs { tab.view?.stopLoading() }
        if privateStore != nil { privateSession?.release() }
        privateStore = nil
        tabs = [Tab(SavedTab())]
        selection = .tab(tabs[0].id)
        groupSelections.removeAll()
        data = BrowserData()
    }

    func savePendingLogin(_ login: SavedLogin) {
        guard !isPrivate else { return }
        pendingLogin = nil
        do { try passwordVault.save(login) }
        catch { passwordError = error.localizedDescription }
    }

    private static let profileSearchKeys = ["address-search-engine", "incognito-search-engine"]
    private static let profileToggleKeys = [
        "address-search", "incognito-address-search", "search-suggestions-enabled",
        "incognito-search-suggestions-enabled", PasswordForms.autofillKey
    ] + BrowserPreference.booleanKeys

    func resetSettings() {
        guard !isPrivate else { return }
        let keys = Self.profileSearchKeys + Self.profileToggleKeys + [
            BrowserPreference.theme, BrowserPreference.bookmarkBar, BrowserPreference.pageZoom,
            BrowserPreference.minimumFontSize, BrowserPreference.downloadsFolder
        ]
        for key in keys { defaults.removeObject(forKey: key) }
        updatePageZoom()
        updateMinimumFont()
    }

    func exportProfile() throws -> ProfileContents {
        guard !isPrivate else { throw ProfileError.invalidFile }
        save()
        var preferences: [String: String] = [:]
        for key in Self.profileSearchKeys + ["local-notes", BrowserPreference.theme, BrowserPreference.bookmarkBar] {
            preferences[key] = defaults.string(forKey: key)
        }
        for key in [BrowserPreference.pageZoom, BrowserPreference.minimumFontSize] {
            if let level = defaults.object(forKey: key) as? Int { preferences[key] = String(level) }
        }
        for key in Self.profileToggleKeys {
            if let value = defaults.object(forKey: key) as? Bool { preferences[key] = String(value) }
        }
        return ProfileContents(browser: data, passwords: try passwordVault.entries(),
                               downloads: downloads.items, preferences: preferences)
    }

    func importProfile(_ profile: ProfileContents) throws -> ProfileImportResult {
        guard !isPrivate else { throw ProfileError.invalidFile }
        let passwords = try passwordVault.merge(profile.passwords)
        save()
        let count = tabs.count
        var merged = data
        var result = ProfileImportResult.merge(profile.browser, into: &merged)
        result.passwords = passwords
        data = merged
        for page in profile.browser.tabs.compactMap(\.page) {
            if let iconURL = page.iconURL { siteIcons.remember(iconURL, for: page.url) }
        }
        tabs += merged.tabs.dropFirst(count).map(Tab.init)
        result.downloads = downloads.importHistory(profile.downloads)
        for key in Self.profileSearchKeys {
            if let value = profile.preferences[key], SearchEngine(rawValue: value) != nil {
                defaults.set(value, forKey: key)
            }
        }
        for key in Self.profileToggleKeys {
            if let value = profile.preferences[key], let flag = Bool(value) { defaults.set(flag, forKey: key) }
        }
        if let value = profile.preferences[BrowserPreference.theme], BrowserTheme(rawValue: value) != nil {
            defaults.set(value, forKey: BrowserPreference.theme)
        }
        if let value = profile.preferences[BrowserPreference.bookmarkBar], BookmarkBarVisibility(rawValue: value) != nil {
            defaults.set(value, forKey: BrowserPreference.bookmarkBar)
        }
        for (key, allowed) in [(BrowserPreference.pageZoom, BrowserPreference.zoomLevels),
                               (BrowserPreference.minimumFontSize, BrowserPreference.fontSizes)] {
            if let value = profile.preferences[key].flatMap(Int.init), allowed.contains(value) {
                defaults.set(value, forKey: key)
            }
        }
        if let notes = profile.preferences["local-notes"], defaults.string(forKey: "local-notes")?.isEmpty != false {
            defaults.set(notes, forKey: "local-notes")
        }
        save()
        return result
    }

    var bookmarkFolders: [BookmarkFolder] { data.bookmarkFolders ?? [] }
    var allBookmarks: [Page] { data.bookmarks + bookmarkFolders.flatMap(\.pages) }

    func bookmarkFolder(containing page: Page) -> UUID? {
        bookmarkFolders.first { $0.pages.contains(where: { $0.url == page.url }) }?.id
    }

    func createBookmarkFolder(_ name: String, parent: UUID? = nil) -> UUID? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isPrivate, !cleanName.isEmpty else { return nil }
        let parentID = bookmarkFolders.first { $0.id == parent }?.id
        if let folder = bookmarkFolders.first(where: {
            $0.parentID == parentID && $0.name.caseInsensitiveCompare(cleanName) == .orderedSame
        }) {
            return folder.id
        }
        let folder = BookmarkFolder(name: cleanName, parentID: parentID)
        data.bookmarkFolders = bookmarkFolders + [folder]
        save()
        return folder.id
    }

    func renameBookmarkFolder(_ id: UUID, to name: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isPrivate, !cleanName.isEmpty,
              let index = bookmarkFolders.firstIndex(where: { $0.id == id }) else { return false }
        data.bookmarkFolders?[index].name = cleanName
        save()
        return true
    }

    func saveBookmark(_ page: Page, folder: UUID?) {
        guard !isPrivate, Address.isWeb(page.url) else { return }
        let folderIndex = bookmarkFolders.firstIndex { $0.id == folder }
        if let folderIndex {
            if let index = bookmarkFolders[folderIndex].pages.firstIndex(where: { $0.url == page.url }) {
                data.bookmarkFolders?[folderIndex].pages[index] = page
            } else {
                removeBookmarkEntries(for: page.url)
                data.bookmarkFolders?[folderIndex].pages.append(page)
            }
        } else if let index = data.bookmarks.firstIndex(where: { $0.url == page.url }) {
            data.bookmarks[index] = page
        } else {
            removeBookmarkEntries(for: page.url)
            data.bookmarks.append(page)
        }
        save()
    }

    func removeBookmarkFolder(_ id: UUID) {
        guard !isPrivate, let index = bookmarkFolders.firstIndex(where: { $0.id == id }) else { return }
        if let folder = data.bookmarkFolders?.remove(at: index) {
            if let parentIndex = bookmarkFolders.firstIndex(where: { $0.id == folder.parentID }) {
                data.bookmarkFolders?[parentIndex].pages.append(contentsOf: folder.pages)
            } else {
                data.bookmarks.append(contentsOf: folder.pages)
            }
            for child in bookmarkFolders.indices where bookmarkFolders[child].parentID == id {
                data.bookmarkFolders?[child].parentID = folder.parentID
            }
            save()
        }
    }

    func removeBookmark(_ page: Page) {
        guard !isPrivate else { return }
        removeBookmarkEntries(for: page.url)
        save()
    }

    private func removeBookmarkEntries(for url: URL) {
        data.bookmarks.removeAll { $0.url == url }
        for index in bookmarkFolders.indices {
            data.bookmarkFolders?[index].pages.removeAll { $0.url == url }
        }
    }

    func deleteVisits(_ ids: Set<UUID>) {
        data.history.removeAll { ids.contains($0.id) }
        save()
    }

    func clearHistory(_ period: ClearPeriod = .all, now: Date = .now) {
        if period == .all {
            data.history.removeAll()
            data.closed.removeAll()
        } else {
            let cutoff = period.cutoff(now: now)
            data.history.removeAll { $0.visitedAt.map { $0 >= cutoff } ?? false }
            data.closed.removeAll { $0.closedAt.map { $0 >= cutoff } ?? false }
        }
        save()
    }

    func clearCookies(_ period: ClearPeriod = .all, now: Date = .now) async {
        await store.removeData(ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: period.cutoff(now: now))
    }

    func recordVisit(_ page: Page, at date: Date = .now) {
        guard !isPrivate else { return }
        data.history.insert(HistoryVisit(page: page, at: date), at: 0)
        save()
    }

    private func updatePage(_ web: WKWebView, completed: Bool) {
        guard let tab = tabs.first(where: { $0.view === web }),
              let url = web.url, Address.isWeb(url) else { return }
        let title = completed ? web.title.flatMap { $0.isEmpty ? nil : $0 } : nil
        let page = Page(title: title ?? url.host ?? url.absoluteString, url: url)
        tab.error = nil
        tab.retryURL = nil
        tab.saved.page = page
        objectWillChange.send()
        if completed { recordVisit(page) } else { save() }
    }

    private func updateTitle(_ web: WKWebView) {
        guard let tab = tabs.first(where: { $0.view === web }), let url = web.url,
              tab.saved.page?.url == url, let title = web.title, !title.isEmpty,
              title != tab.saved.page?.title else { return }
        tab.saved.page?.title = title
        if let index = data.history.firstIndex(where: { $0.url == url }) {
            data.history[index].title = title
        }
        objectWillChange.send()
        save()
    }

    func webView(_ web: WKWebView, didCommit navigation: WKNavigation!) {
        updatePage(web, completed: false)
    }

    func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
        updatePage(web, completed: true)
        updateSiteIcon(web)
    }

    private func updateSiteIcon(_ web: WKWebView) {
        guard let url = web.url, Address.isWeb(url) else { return }
        Task { [weak self, weak web] in
            guard let self, let web else { return }
            let result = try? await web.callAsyncJavaScript("""
                const links = Array.from(document.querySelectorAll('link[rel]'));
                const icons = links.filter(link => link.rel.toLowerCase().split(/\\s+/).includes('icon'));
                const touch = links.filter(link => link.rel.toLowerCase() === 'apple-touch-icon');
                icons.sort((a, b) => Number(a.type === 'image/svg+xml') - Number(b.type === 'image/svg+xml'));
                return [...icons, ...touch].map(link => link.href).find(value => /^https?:/i.test(value)) ?? null;
                """, arguments: [:], in: nil, contentWorld: .defaultClient)
            guard web.url == url, let text = result as? String, let iconURL = URL(string: text),
                  Address.isWeb(iconURL), let tab = tabs.first(where: { $0.view === web }),
                  tab.saved.page?.url == url, tab.saved.page?.iconURL != iconURL else { return }
            tab.saved.page?.iconURL = iconURL
            siteIcons.remember(iconURL, for: url)
            objectWillChange.send()
            save()
        }
    }

    func webView(_ web: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showFailure(in: web, error: error)
    }

    func webView(_ web: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showFailure(in: web, error: error)
    }

    private func showFailure(in web: WKWebView, error: Error) {
        let failure = error as NSError
        if failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled { return }
        guard let tab = tabs.first(where: { $0.view === web }) else { return }
        tab.error = error.localizedDescription
        tab.retryURL = (failure.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? tab.retryURL
        objectWillChange.send()
    }

    func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.shouldPerformDownload, let url = action.request.url,
           Address.isWeb(url) || url.scheme == "blob" || url.scheme == "data" {
            decisionHandler(.download)
            return
        }
        if action.targetFrame?.isMainFrame != false {
            if let file = action.request.url, file.isFileURL,
               let tab = tabs.first(where: { $0.view === web }), tab.saved.localFile == file {
                decisionHandler(.allow)
                return
            }
            guard let url = action.request.url, Address.isWeb(url) else {
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ web: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (response.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?
            .split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespaces).lowercased()
        let isPDF = response.response.mimeType?.lowercased() == "application/pdf"
        let preview = !isPDF || BrowserPreference.enabled(defaults, BrowserPreference.previewPDF)
        decisionHandler(response.canShowMIMEType && disposition != "attachment" && preview ? .allow : .download)
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let camera = BrowserPreference.enabled(defaults, BrowserPreference.allowCamera)
        let microphone = BrowserPreference.enabled(defaults, BrowserPreference.allowMicrophone)
        let allowed: Bool
        switch type {
        case .camera: allowed = camera
        case .microphone: allowed = microphone
        case .cameraAndMicrophone: allowed = camera && microphone
        @unknown default: allowed = false
        }
        decisionHandler(allowed ? .prompt : .deny)
    }

    func webView(_ web: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url, Address.isWeb(url) else { return nil }
        let source = tabs.first { $0.view === web }
        return newTab(SavedTab(group: source?.saved.group), configuration: configuration).view
    }

    func webView(_ web: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = downloads
    }

    func webView(_ web: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = downloads
    }
}
