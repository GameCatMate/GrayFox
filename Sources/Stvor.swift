import SwiftUI
import WebKit

@main
struct MyBroApp: App {
    @StateObject private var browser: Browser
    @AppStorage(BrowserPreference.theme) private var theme: BrowserTheme = .system

    init() {
        let browser = Browser()
        _browser = StateObject(wrappedValue: browser)
        if CommandLine.arguments.contains("--mybro-import") {
            Task { await Self.importAtLaunch(into: browser) }
        }
    }

    var body: some Scene {
        Window("myBro", id: "browser") {
            BrowserView(browser: browser)
                .preferredColorScheme(theme.colorScheme)
                .onOpenURL { browser.openExternal($0) }
        }
        .defaultSize(width: 1160, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands { BrowserCommands() }

        Window("Избранное", id: BookmarkManager.windowID) {
            BookmarkManager(browser: browser)
                .preferredColorScheme(theme.colorScheme)
                .frame(minWidth: 440, minHeight: 320)
        }
        .defaultSize(width: 760, height: 540)
        .commandsRemoved()

        WindowGroup("myBro · Инкогнито", id: "private") {
            BrowserView(browser: Browser(isPrivate: true, privateSession: .shared))
                .preferredColorScheme(theme.colorScheme)
        }
        .defaultSize(width: 1060, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands { BrowserCommands() }
    }

    @MainActor private static func importAtLaunch(into browser: Browser) async {
        do {
            guard let inputs = try BrowserMigration.Inputs.launchArguments(CommandLine.arguments) else { return }
            browser.show(.profile)
            browser.migrationStatus = "Перенос данных…"
            var report = try await Task.detached { try BrowserMigration.inspect(inputs) }.value
            report.contents.preferences[PasswordForms.autofillKey] = "true"
            let result = try browser.importProfile(report.contents)
            let message = ([result.message] + report.warnings).joined(separator: " ")
            UserDefaults.standard.set(message, forKey: "last-profile-import-report")
            browser.migrationStatus = message
        } catch {
            let message = "Импорт не завершён. " + error.localizedDescription
            UserDefaults.standard.set(message, forKey: "last-profile-import-report")
            browser.migrationStatus = message
        }
    }
}

private struct BrowserWindowActions {
    let browser: Browser
    let showHistory: () -> Void
    let showSettings: () -> Void
    let focusAddress: () -> Void
    let openPrivateWindow: () -> Void
}

private struct FocusedBrowserKey: FocusedValueKey {
    typealias Value = BrowserWindowActions
}

private extension FocusedValues {
    var browserActions: BrowserWindowActions? {
        get { self[FocusedBrowserKey.self] }
        set { self[FocusedBrowserKey.self] = newValue }
    }
}

private struct BrowserCommands: Commands {
    @FocusedValue(\.browserActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Новая вкладка") { actions?.browser.newTab() }
                .keyboardShortcut("t")
                .disabled(actions == nil)
            Button("Новое окно инкогнито") { actions?.openPrivateWindow() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button("Адресная строка") { actions?.focusAddress() }
                .keyboardShortcut("l")
                .disabled(actions == nil)
            Button("Вернуть закрытую вкладку") { actions?.browser.reopen() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(actions?.browser.data.closed.isEmpty != false)
        }
        CommandMenu("История") {
            Button("Показать историю") { actions?.showHistory() }
                .keyboardShortcut("y")
                .disabled(actions?.browser.isPrivate != false)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Настройки…") { actions?.showSettings() }
                .keyboardShortcut(",")
                .disabled(actions == nil)
        }
    }
}

struct BrowserView: View {
    @StateObject var browser: Browser
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(BrowserPreference.reduceMotion) private var reduceBrowserMotion = false
    @AppStorage(BrowserPreference.bookmarkBar) private var bookmarkBarVisibility: BookmarkBarVisibility = .always
    @AppStorage(BrowserPreference.bookmarkIcons) private var bookmarkBarIcons = true
    @AppStorage(BrowserPreference.startClock) private var startClock = false
    @AppStorage(BrowserPreference.startSearch) private var startSearch = true
    @AppStorage(BrowserPreference.startTiles) private var startTiles = true
    @AppStorage(BrowserPreference.pageZoom) private var defaultZoom = 100
    @AppStorage(BrowserPreference.minimumFontSize) private var minimumFont = 0
    @AppStorage(BrowserPreference.pageSnapshots) private var allowsPageSnapshots = true
    @Environment(\.openWindow) private var openWindow
    @State private var addressFocused = false
    @State private var addressFocusRequest = 0
    @State private var startFocused = false
    @State private var startFocusRequest = 0
    @FocusState private var findFocused: Bool
    @AppStorage("address-search") private var searchEnabled = true
    @AppStorage("incognito-address-search") private var privateSearchEnabled = true
    @AppStorage("search-suggestions-enabled") private var normalSuggestions = true
    @AppStorage("incognito-search-suggestions-enabled") private var privateSuggestions = false
    @AppStorage("address-search-engine") private var normalSearchEngine = SearchEngine.google
    @AppStorage("incognito-search-engine") private var privateSearchEngine = SearchEngine.duckDuckGo
    @State private var address = ""
    @State private var inputError = false
    @AppStorage("local-notes") private var notes = ""
    @State private var showsNotes = false
    @State private var groupDialog = false
    @State private var groupName = ""
    @State private var groupToRename: String?
    @State private var tabForNewGroup: Tab?
    @State private var groupError = false
    @State private var findVisible = false
    @State private var findText = ""
    @State private var findStatus = ""
    @State private var snapshotError: String?
    @State private var hoveredGroup: String?
    @State private var hoveredTabID: UUID?
    @State private var hoveredTabCloseID: UUID?
    @AppStorage("tab-groups-width") private var preferredGroupWidth = 0.0
    @State private var naturalGroupWidth: CGFloat = 270
    @State private var groupResizeStart: CGFloat?
    @GestureState private var resizingGroups = false
    @State private var hoveredGroupDivider = false
    @State private var tabGroupControlsWidth: CGFloat = 0
    @State private var tabScrollOffset: CGFloat = 0
    @State private var tabReorder: TabStripReorder<UUID>?
    @State private var groupReorder: TabStripReorder<String>?
    @GestureState private var reorderingStrip = false
    @State private var hoveredTabViewport = false
    @State private var hoveredGroupViewport = false
    @State private var tabFrames: [UUID: CGRect] = [:]
    @State private var groupFrames: [String: CGRect] = [:]
    @State private var tabContentFrame = CGRect.zero
    @State private var groupContentFrame = CGRect.zero
    @State private var tabViewportFrame = CGRect.zero
    @State private var groupViewportFrame = CGRect.zero
    @State private var editingAddress = false
    @State private var suggestionIndex: Int?
    @State private var fetchedSuggestions: (request: SearchSuggestionRequest, values: [String])?
    @State private var bookmarkPopover: Page?
    @State private var showsRecentDownloads = false
    @State private var zoomFeedback: UUID?
    @State private var clearingCookies = false
    @State private var cookiesCleared = false
    @State private var clearPeriod: ClearPeriod = .hour
    @State private var selectedVisits: Set<UUID> = []

    private var engine: Binding<SearchEngine> {
        browser.isPrivate ? $privateSearchEngine : $normalSearchEngine
    }

    private var search: Binding<Bool> {
        browser.isPrivate ? $privateSearchEnabled : $searchEnabled
    }

    private var networkSuggestions: Binding<Bool> {
        browser.isPrivate ? $privateSuggestions : $normalSuggestions
    }

    private var isAddressFocused: Bool { addressFocused || startFocused }
    private var reduceMotion: Bool { systemReduceMotion || reduceBrowserMotion }

    private var showsBookmarkBar: Bool {
        guard !browser.isPrivate, bookmarkBarVisibility != .hidden else { return false }
        if bookmarkBarVisibility == .always { return true }
        return browser.active?.saved.page == nil && browser.active?.saved.internalPage == nil && browser.active?.view == nil
    }

    var body: some View {
        let request = suggestionRequest
        VStack(spacing: 0) {
            tabStrip
            navigation
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.background)
                .zIndex(1)
            if inputError {
                Text("Введите адрес HTTP или HTTPS\(search.wrappedValue ? " либо поисковый запрос" : "").")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            if showsBookmarkBar {
                BookmarkBar(browser: browser, showsIcons: bookmarkBarIcons) { bookmarkPopover = browser.active?.saved.page }
            }
            Rectangle().fill(.quaternary).frame(height: 1)
            if findVisible { findBar }
            content
        }
        .frame(minWidth: 650, minHeight: 430)
        .ignoresSafeArea(.container, edges: .top)
        .overlayPreferenceValue(AddressSuggestionAnchor.self) { anchor in
            if let anchor {
                GeometryReader { geometry in
                    let bounds = geometry[anchor]
                    AddressSuggestionList(
                        suggestions: addressSuggestions, selectedIndex: suggestionIndex ?? 0,
                        maxHeight: max(32, geometry.size.height - bounds.maxY - 16),
                        query: Address.searchQuery(address), engine: engine.wrappedValue,
                        isOpen: { openTab(for: $0) != nil }, choose: submitSuggestion
                    )
                    .frame(width: bounds.width)
                    .offset(x: bounds.minX, y: bounds.maxY + 4)
                }
            }
        }
        .task(id: request) {
            guard let request else { return }
            do {
                try await Task.sleep(for: .milliseconds(220))
                let values = try await request.fetch()
                try Task.checkCancellation()
                fetchedSuggestions = (request, values)
            } catch {
                // The local suggestions stay available if the request fails or is cancelled.
            }
        }
        .modifier(DownloadsPopover(downloads: browser.downloads, isPresented: $showsRecentDownloads) {
            browser.show(.downloads)
        })
        .task(id: zoomFeedback) {
            guard zoomFeedback != nil else { return }
            do {
                try await Task.sleep(for: .seconds(2))
                try Task.checkCancellation()
                zoomFeedback = nil
            } catch { }
        }
        .background { if browser.isPrivate { PrivateWindowMarker() } }
        .background {
            BrowserTabKeyHandler(step: browser.stepTab, zoom: zoom)
                .frame(width: 0, height: 0)
        }
        .focusedSceneValue(\.browserActions, BrowserWindowActions(
            browser: browser, showHistory: showHistory, showSettings: { browser.show(.settings) },
            focusAddress: focusAddress, openPrivateWindow: { openWindow(id: "private") }
        ))
        .onAppear {
            browser.beginPrivateSession()
            if let tab = browser.active, tab.saved.page != nil || tab.saved.localFile != nil { browser.prepare(tab) }
            syncAddress()
            if address.isEmpty { focusStart() }
        }
        .onDisappear { browser.endPrivateSession() }
        .onChange(of: defaultZoom) { browser.updatePageZoom() }
        .onChange(of: minimumFont) { browser.updateMinimumFont() }
        .onChange(of: browser.activeID) {
            showsRecentDownloads = false
            zoomFeedback = nil
            addressFocused = false
            startFocused = false
            syncAddress()
            if address.isEmpty { focusStart() }
        }
        .onChange(of: browser.active?.saved.page?.url) {
            if !isAddressFocused { syncAddress() }
        }
        .onChange(of: isAddressFocused) {
            if !isAddressFocused { editingAddress = false }
        }
        .sheet(isPresented: $showsNotes) { notesSheet }
        .alert("Сохранить пароль?", isPresented: Binding(
            get: { browser.pendingLogin != nil },
            set: { if !$0 { browser.pendingLogin = nil } }
        ), presenting: browser.pendingLogin) { login in
            Button("Сохранить") { browser.savePendingLogin(login) }
            Button("Не сейчас", role: .cancel) { browser.pendingLogin = nil }
        } message: { login in
            Text(login.origin.url.absoluteString + " · " + login.username)
        }
        .alert("Менеджер паролей", isPresented: Binding(
            get: { browser.passwordError != nil },
            set: { if !$0 { browser.passwordError = nil } }
        )) {
            Button("Закрыть", role: .cancel) {}
        } message: { Text(browser.passwordError ?? "") }
        .alert(groupToRename == nil ? "Новая группа вкладок" : "Переименовать группу", isPresented: $groupDialog) {
            TextField("Название", text: $groupName)
            Button("Отмена", role: .cancel) {}
            Button(groupToRename == nil ? "Создать" : "Сохранить") {
                if let group = groupToRename {
                    groupError = !browser.renameGroup(group, to: groupName)
                } else {
                    groupError = !browser.createGroup(groupName, containing: tabForNewGroup)
                }
            }
            .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Такое название уже используется", isPresented: $groupError) {
            Button("Изменить название") { groupDialog = true }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Снимок не сохранён", isPresented: Binding(
            get: { snapshotError != nil }, set: { if !$0 { snapshotError = nil } }
        )) {
            Button("Закрыть", role: .cancel) {}
        } message: {
            Text(snapshotError ?? "")
        }
    }

    private var tabStrip: some View {
        let tabs = browser.visibleTabs
        let gap = TabStripMetrics.controlGap
        let controlWidth = TabStripMetrics.controlWidth
        return GeometryReader { geometry in
            let fixedWidth = tabGroupControlsWidth + controlWidth + gap
                + (tabs.isEmpty ? 0 : gap)
                + (browser.isPrivate ? controlWidth + gap : 0)
            let layout = TabStripMetrics(available: max(0, geometry.size.width - fixedWidth), count: tabs.count)
            ScrollViewReader { scroll in
                HStack(spacing: gap) {
                    tabGroupControls(available: geometry.size.width - (browser.isPrivate ? controlWidth + gap : 0))
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                            tabGroupControlsWidth = $0
                        }
                    if !tabs.isEmpty {
                        tabViewport(tabs, layout: layout, scroll: scroll)
                            .overlay(alignment: .leading) {
                                tabScrollButton(forward: false, tabs: tabs, layout: layout, scroll: scroll)
                            }
                            .overlay(alignment: .trailing) {
                                tabScrollButton(forward: true, tabs: tabs, layout: layout, scroll: scroll)
                            }
                    }
                    icon("plus", "Новая вкладка") { browser.newTab() }
                        .frame(width: controlWidth)
                    if browser.isPrivate {
                        Image(systemName: "eye.slash")
                            .frame(width: controlWidth)
                            .accessibilityLabel("Частный просмотр")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: tabs.count)
            }
        }
        .padding(.leading, 82)
        .padding(.trailing, 12)
        .frame(height: 36)
        .background(chromeColor)
        .overlay(alignment: .leading) { FullscreenWindowButtons().frame(width: 82, height: 36) }
        .background(TabStripWindowInteraction(blocked: hoveredTabID != nil || hoveredGroup != nil
                                             || hoveredGroupDivider || resizingGroups || reorderingStrip
                                             || hoveredTabViewport || hoveredGroupViewport))
        .onChange(of: reorderingStrip) {
            if !reorderingStrip {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    tabReorder = nil
                    groupReorder = nil
                }
            }
        }
    }

    private func tabGroupControls(available: CGFloat) -> some View {
        let width = TabStripMetrics.groupWidth(preferred: preferredGroupWidth,
                                              content: naturalGroupWidth, available: available)
        return HStack(spacing: TabStripMetrics.controlGap) {
            if !browser.data.groups.isEmpty {
                ScrollViewReader { scroll in
                    ScrollView(.horizontal) {
                        groupChips
                            .fixedSize(horizontal: true, vertical: false)
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                                naturalGroupWidth = $0
                            }
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: width)
                    .highPriorityGesture(groupReorderGesture)
                    .onHover { hoveredGroupViewport = $0 }
                    .onDisappear { hoveredGroupViewport = false }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        groupViewportFrame = $0
                    }
                    .task(id: groupReorder?.scrollDirection(in: groupViewportFrame) ?? 0) {
                        await scrollWhileDragging({ groupReorder }, content: { groupContentFrame },
                                                  viewport: { groupViewportFrame }, spacing: 4, scroll: scroll)
                    }
                }
            }
            allGroupsMenu
            if browser.data.groups.isEmpty {
                Divider().frame(height: 20)
            } else {
                groupResizeHandle(width: width, available: available)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func groupResizeHandle(width: CGFloat, available: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 20)
            .frame(width: TabStripMetrics.groupResizeHandleWidth, height: 30)
            .contentShape(Rectangle())
            .onHover { hovering in
                hoveredGroupDivider = hovering
                if hovering || groupResizeStart != nil { NSCursor.resizeLeftRight.set() }
                else { NSCursor.arrow.set() }
            }
            .highPriorityGesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .updating($resizingGroups) { _, resizing, _ in resizing = true }
                .onChanged { value in
                    if groupResizeStart == nil { groupResizeStart = width }
                    preferredGroupWidth = TabStripMetrics.groupWidth(
                        preferred: max(48, (groupResizeStart ?? width) + value.translation.width),
                        content: naturalGroupWidth, available: available
                    )
                    NSCursor.resizeLeftRight.set()
                })
            .onChange(of: resizingGroups) {
                if !resizingGroups {
                    groupResizeStart = nil
                    if !hoveredGroupDivider { NSCursor.arrow.set() }
                }
            }
            .accessibilityElement()
            .accessibilityIdentifier("tab-group-resize")
            .accessibilityLabel("Ширина области групп вкладок")
            .accessibilityValue("\(Int(width))")
            .accessibilityAdjustableAction { direction in
                let change: CGFloat = direction == .increment ? 24 : -24
                preferredGroupWidth = TabStripMetrics.groupWidth(
                    preferred: width + change, content: naturalGroupWidth, available: available
                )
            }
            .help("Потяните, чтобы изменить ширину области групп")
            .onDisappear {
                hoveredGroupDivider = false
                groupResizeStart = nil
                NSCursor.arrow.set()
            }
    }

    private var chromeColor: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color(red: 0.92, green: 0.91, blue: 0.94)
    }

    private var groupChips: some View {
        let order = groupReorder?.arranged(browser.data.groups) ?? browser.data.groups
        return HStack(spacing: 4) {
            ForEach(order, id: \.self) { group in
                groupChip(group)
                    .id(group)
                    .contextMenu { groupActions(group) }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: order)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            groupContentFrame = $0
            if var drag = groupReorder {
                drag.update(translation: drag.translation, location: drag.location,
                            origin: $0.minX, spacing: 4, viewport: groupViewportFrame)
                groupReorder = drag
            }
        }
    }

    private func tabViewport(_ tabs: [Tab], layout: TabStripMetrics, scroll: ScrollViewProxy) -> some View {
        let coordinateSpace = "myBro.tabViewport"
        let order = tabReorder?.arranged(tabs.map(\.id)) ?? tabs.map(\.id)
        let available = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        return ScrollView(.horizontal) {
            HStack(spacing: TabStripMetrics.spacing) {
                ForEach(order, id: \.self) { id in
                    if let tab = available[id] { tabRow(tab, width: layout.tabWidth).id(id) }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: order)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                tabContentFrame = $0
                if var drag = tabReorder {
                    drag.update(translation: drag.translation, location: drag.location,
                                origin: $0.minX, spacing: TabStripMetrics.spacing, viewport: tabViewportFrame)
                    tabReorder = drag
                }
            }
            .onGeometryChange(for: CGFloat.self) {
                max(0, -$0.frame(in: .named(coordinateSpace)).minX)
            } action: {
                tabScrollOffset = $0
            }
        }
        .coordinateSpace(name: coordinateSpace)
        .scrollIndicators(.hidden)
        .frame(width: layout.viewport)
        .highPriorityGesture(tabReorderGesture)
        .onHover { hoveredTabViewport = $0 }
        .onDisappear { hoveredTabViewport = false }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            tabViewportFrame = $0
        }
        .task(id: tabReorder?.scrollDirection(in: tabViewportFrame) ?? 0) {
            await scrollWhileDragging({ tabReorder }, content: { tabContentFrame },
                                      viewport: { tabViewportFrame }, spacing: TabStripMetrics.spacing, scroll: scroll)
        }
        .task(id: browser.activeID) {
            guard let id = browser.activeID else { return }
            await Task.yield()
            guard !Task.isCancelled, browser.activeID == id else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { scroll.scrollTo(id) }
        }
        .onChange(of: layout.available) { previous, current in
            if current < previous, let id = browser.activeID {
                scroll.scrollTo(id)
            }
        }
    }

    private func tabScrollButton(forward: Bool, tabs: [Tab], layout: TabStripMetrics,
                                 scroll: ScrollViewProxy) -> some View {
        let symbol = forward ? "chevron.right" : "chevron.left"
        let label = forward ? "Прокрутить вкладки вправо" : "Прокрутить вкладки влево"
        let visible = forward ? layout.canScrollRight(at: tabScrollOffset) : layout.canScrollLeft(at: tabScrollOffset)
        return icon(symbol, label) {
            let index = layout.targetIndex(from: tabScrollOffset, forward: forward)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                scroll.scrollTo(tabs[index].id, anchor: .leading)
            }
        }
        .frame(width: TabStripMetrics.controlWidth, height: 36)
        .background(chromeColor)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .animation(reduceMotion ? nil : .smooth(duration: 0.20), value: visible)
    }

    private var allGroupsMenu: some View {
        Menu {
            Button("Создать группу…") { editGroup() }
                .keyboardShortcut("g", modifiers: [.command, .option])
            if !browser.data.groups.isEmpty {
                Divider()
                Button("Вкладки без группы") { browser.selectGroup(nil) }
            }
            ForEach(browser.data.groups, id: \.self) { group in
                Button(group) { browser.selectGroup(group) }
            }
        } label: {
            Label("Все группы", systemImage: "chevron.down").labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Все группы")
        .accessibilityLabel("Все группы")
    }

    private func groupChip(_ group: String) -> some View {
        let selected = group == browser.activeGroup
        let dropTarget = tabReorder.map { groupViewportFrame.contains($0.location)
            && groupFrames[group]?.contains($0.location) == true } ?? false
        let count = browser.tabs.count { $0.saved.group == group }
        let tint = browser.groupTint(for: group).color
        return Button { browser.selectGroup(group) } label: {
            HStack(spacing: 5) {
                Text(count.formatted()).monospacedDigit()
                    .padding(.horizontal, 4)
                    .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                Text(group).lineLimit(1)
            }
            .font(.caption.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 6)
            .frame(height: 26)
            .background(tint.opacity(selected || dropTarget ? 0.30 : 0.13),
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .modifier(TabStripDragItem(
            offset: groupReorder?.offset(for: group, origin: groupContentFrame.minX, spacing: 4,
                                        viewport: groupViewportFrame) ?? 0,
            active: groupReorder?.item == group,
            measure: { groupFrames[group] = $0 }
        ))
        .onHover { hovering in
            if hovering { hoveredGroup = group }
            else if hoveredGroup == group { hoveredGroup = nil }
        }
        .onDisappear { if hoveredGroup == group { hoveredGroup = nil } }
        .help(group)
        .accessibilityLabel(group)
        .accessibilityValue(count.formatted())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func groupActions(_ group: String) -> some View {
        Button("Переименовать…") { editGroup(group) }
        Menu("Цвет группы") {
            ForEach(GroupTint.allCases, id: \.self) { tint in
                Button {
                    browser.setGroupTint(tint, for: group)
                } label: {
                    if browser.groupTint(for: group) == tint {
                        Label(tint.rawValue, systemImage: "checkmark")
                    } else {
                        Text(tint.rawValue)
                    }
                }
            }
        }
        Button("Удалить группу", role: .destructive) { browser.removeGroup(group) }
    }

    private var navigation: some View {
        HStack(spacing: 8) {
            icon("chevron.left", "Назад", inAddressToolbar: true) { browser.active?.view?.goBack() }
                .keyboardShortcut("[")
            icon("chevron.right", "Вперёд", inAddressToolbar: true) { browser.active?.view?.goForward() }
                .keyboardShortcut("]")
            icon("arrow.clockwise", "Обновить", inAddressToolbar: true) { browser.reload() }
                .keyboardShortcut("r")
            addressBox()
            if browser.canZoomPage && (zoomFeedback != nil || browser.pageZoomPercent != browser.defaultPageZoomPercent) {
                zoomIndicator
            }
            icon("arrow.right.circle", "Перейти", inAddressToolbar: true) { submitAddress() }
            if !browser.isPrivate {
                bookmarkButton
            }
            DownloadsButton(downloads: browser.downloads) { showsRecentDownloads.toggle() }
            browserMenu
        }
    }

    private var zoomIndicator: some View {
        let percent = browser.pageZoomPercent
        let defaultPercent = browser.defaultPageZoomPercent
        let symbol = percent < defaultPercent ? "minus.magnifyingglass"
            : percent > defaultPercent ? "plus.magnifyingglass" : "magnifyingglass"
        return Label {
            Text("\(percent) %").monospacedDigit().fontWeight(.medium)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: AddressToolbarMetrics.symbolSize))
        }
        .padding(.horizontal, 10)
        .frame(height: AddressToolbarMetrics.controlSize)
        .fixedSize(horizontal: true, vertical: false)
        .background(Color(nsColor: .textBackgroundColor), in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.13)).allowsHitTesting(false) }
        .accessibilityLabel("Масштаб \(percent) процентов")
    }

    private var browserMenu: some View {
        Menu {
            Button {
                openWindow(id: "private")
            } label: {
                Label("Режим инкогнито", systemImage: "eyeglasses")
            }
            if !browser.isPrivate {
                Menu {
                    Button("Открыть историю") { showHistory() }
                    reopenTabButton
                } label: {
                    Label("История", systemImage: "clock")
                }
                Menu {
                    Button("Менеджер закладок") { browser.show(.bookmarks) }
                    Button("Открыть в отдельном окне") { openWindow(id: BookmarkManager.windowID) }
                    Button("Добавить текущую страницу…") { bookmarkPopover = browser.active?.saved.page }
                        .disabled(browser.active?.saved.page == nil)
                } label: {
                    Label("Закладки", systemImage: "bookmark")
                }
                Button {
                    browser.show(.passwords)
                } label: {
                    Label("Пароли и данные", systemImage: "key")
                }
            }
            Button {
                browser.show(.downloads)
            } label: {
                Label("Загрузки", systemImage: "arrow.down.to.line")
            }
            if !browser.isPrivate {
                Button {
                    browser.show(.extensions)
                } label: {
                    Label("Расширения", systemImage: "puzzlepiece.extension")
                }
            }
            Menu {
                Button("Адресная строка") { focusAddress() }
                Button("Закрыть вкладку") {
                    if let tab = browser.active { browser.close(tab) }
                }
                .keyboardShortcut("w")
                .disabled(browser.active == nil)
                if browser.isPrivate { reopenTabButton }
                Button("Следующая вкладка") { browser.stepTab(1) }
                Button("Предыдущая вкладка") { browser.stepTab(-1) }
                Divider()
                Button("Найти на странице") { findVisible = true; findFocused = true }.keyboardShortcut("f")
                Button("Увеличить масштаб") { _ = zoom(.increase) }.keyboardShortcut("+")
                    .disabled(!browser.canZoomPage)
                Button("Уменьшить масштаб") { _ = zoom(.decrease) }.keyboardShortcut("-")
                    .disabled(!browser.canZoomPage)
                Button("Сбросить масштаб") { _ = zoom(.reset) }.keyboardShortcut("0")
                    .disabled(!browser.canZoomPage)
                Button("Печать…") { printPage() }.keyboardShortcut("p")
                Button("Снимок страницы…") { takeSnapshot() }
                    .disabled(!allowsPageSnapshots || browser.active?.saved.page == nil || browser.active?.error != nil)
                if !browser.isPrivate {
                    Divider()
                    Button("Перенос профиля") { browser.show(.profile) }
                    Button("Заметки") { showsNotes = true }
                }
            } label: {
                Label("Дополнительно", systemImage: "ellipsis")
            }
            Divider()
            Menu {
                Button("О myBro") { NSApplication.shared.orderFrontStandardAboutPanel(nil) }
            } label: {
                Label("Помощь", systemImage: "questionmark.circle")
            }
            Button {
                browser.show(.settings)
            } label: {
                Label("Настройки", systemImage: "gearshape")
            }
        } label: {
            Label("Меню браузера", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .font(.system(size: AddressToolbarMetrics.symbolSize))
                .frame(width: AddressToolbarMetrics.controlSize, height: AddressToolbarMetrics.controlSize)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Меню браузера")
    }

    private var reopenTabButton: some View {
        Button("Вернуть закрытую вкладку") { browser.reopen() }
            .disabled(browser.data.closed.isEmpty)
    }

    private var suggestionRequest: SearchSuggestionRequest? {
        guard isAddressFocused, editingAddress, search.wrappedValue, networkSuggestions.wrappedValue,
              let query = Address.networkQuery(address) else { return nil }
        return SearchSuggestionRequest(engine: engine.wrappedValue, query: query)
    }

    private var addressSuggestions: [AddressSuggestion] {
        guard isAddressFocused, editingAddress else { return [] }
        let openPages = browser.tabs.filter { $0.id != browser.activeID }.compactMap { $0.saved.page }
        let localPages = openPages + browser.data.history.map(\.page) + browser.allBookmarks + Address.suggestedSites
        var sites = Address.suggestions(for: address, pages: localPages)
        var result: [AddressSuggestion] = []
        if let url = Address.navigationURL(address) {
            let page = sites.first { $0.url == url } ?? Page(title: url.host ?? address, url: url)
            sites.removeAll { $0.url == url }
            result.append(.site(page))
        } else if let first = sites.first, Address.completesHost(address, with: first) {
            result.append(.site(sites.removeFirst()))
        }
        if search.wrappedValue, let query = Address.searchQuery(address) {
            result.append(.search(query))
        }
        result += sites.prefix(4).map(AddressSuggestion.site)
        if let fetchedSuggestions, fetchedSuggestions.request == suggestionRequest {
            result += fetchedSuggestions.values.prefix(max(0, 8 - result.count)).map(AddressSuggestion.search)
        }
        return result
    }

    private func addressBox(isStart: Bool = false) -> some View {
        let focus = isStart ? $startFocused : $addressFocused
        let suggestions = focus.wrappedValue ? addressSuggestions : []
        let selected = suggestionIndex ?? 0
        let currentSuggestion = suggestions.indices.contains(selected) ? suggestions[selected] : suggestions.first
        let symbolSize = isStart ? 16 : AddressToolbarMetrics.symbolSize
        let shape = RoundedRectangle(cornerRadius: isStart ? 12 : 10)
        return HStack(spacing: 8) {
            if currentSuggestion?.isSearch == true {
                SearchEngineIcon(engine: engine.wrappedValue, size: symbolSize)
            } else {
                Image(systemName: currentSuggestion == nil && isStart ? "magnifyingglass" : "globe")
                    .foregroundStyle(.secondary)
                    .font(isStart ? nil : .system(size: symbolSize))
                    .frame(width: symbolSize)
                    .accessibilityHidden(true)
            }
            BrowserAddressField(
                text: address,
                placeholder: isStart ? (search.wrappedValue ? "Адрес или поиск" : "Адрес сайта") : nil,
                focused: focus, focusRequest: isStart ? startFocusRequest : addressFocusRequest,
                edited: { value in
                    address = value
                    inputError = false
                    editingAddress = true
                    suggestionIndex = nil
                },
                handle: handleAddressCommand
            )
            .frame(height: 20)
            if isStart { icon("arrow.right", "Перейти") { submitAddress() } }
        }
        .padding(.horizontal, isStart ? 12 : 10)
        .padding(.vertical, isStart ? 8 : 0)
        .frame(height: isStart ? nil : AddressToolbarMetrics.controlSize)
        .background(Color(nsColor: .textBackgroundColor), in: shape)
        .overlay {
            shape.strokeBorder(focus.wrappedValue ? Color.accentColor : .secondary.opacity(0.22))
                .allowsHitTesting(false)
        }
        .anchorPreference(key: AddressSuggestionAnchor.self, value: .bounds) { suggestions.isEmpty ? nil : $0 }
    }

    private func openTab(for page: Page) -> Tab? {
        browser.tabs.first { $0.id != browser.activeID && $0.saved.page?.url == page.url }
    }

    private var bookmarkButton: some View {
        let saved = browser.allBookmarks.contains { $0.url == browser.active?.saved.page?.url }
        return icon(saved ? "star.fill" : "star", saved ? "Закладка" : "Добавить страницу в закладки",
                    inAddressToolbar: true) {
            bookmarkPopover = browser.active?.saved.page
        }
        .keyboardShortcut("d")
        .disabled(browser.active?.saved.page == nil)
        .popover(item: $bookmarkPopover, arrowEdge: .bottom) { page in
            BookmarkEditor(browser: browser, page: page, openManager: {
                openWindow(id: BookmarkManager.windowID)
            }) { bookmarkPopover = nil }
        }
    }

    private func tabRow(_ tab: Tab, width: CGFloat) -> some View {
        let selected = tab.id == browser.activeID
        let showTitle = width >= 62
        let showClose = selected && hoveredTabID == tab.id
        let centeredClose = width <= TabStripMetrics.minimumWidth + 0.5
        let symbol = tab.saved.pinned ? "pin.fill" : "globe"
        let background: Color = selected || hoveredTabID == tab.id
            ? (colorScheme == .dark ? Color(white: 0.24) : .white)
            : (colorScheme == .dark ? Color(white: 0.15) : .black.opacity(0.08))
        return Button { browser.select(tab) } label: {
            HStack(spacing: 5) {
                Group {
                    if let page = tab.saved.page {
                        SiteIcon(page: page, icons: browser.siteIcons)
                            .overlay(alignment: .bottomTrailing) {
                                if tab.saved.pinned {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 7))
                                        .padding(1)
                                        .background(.background, in: Circle())
                                        .offset(x: 3, y: 3)
                                }
                            }
                    } else {
                        Image(systemName: symbol)
                    }
                }
                .frame(width: 16, height: 16)
                .opacity(showClose && width < 48 ? 0 : 1)
                if showTitle { Text(tab.title).lineLimit(1) }
            }
            .font(.subheadline)
            .padding(.leading, showTitle ? 8 : 0)
            .padding(.trailing, showTitle ? 24 : 0)
            .frame(maxWidth: .infinity, alignment: showTitle ? .leading : .center)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .help(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: Text("Закрыть вкладку")) { browser.close(tab) }
        .frame(width: width)
        .overlay(alignment: centeredClose ? .center : .trailing) {
            if showClose {
                Button { browser.close(tab) } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .frame(height: 24)
                        .padding(.horizontal, 3)
                        .background {
                            Circle().fill(hoveredTabCloseID == tab.id ? Color.primary.opacity(0.16) : .clear)
                                .frame(width: 16, height: 16)
                        }
                        .background(background)
                        .frame(width: centeredClose ? 20 : min(22, max(8, width / 2 - 4)), height: 30,
                               alignment: centeredClose ? .center : .trailing)
                        .padding(.trailing, centeredClose ? 0 : 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Закрыть \(tab.title)")
                .accessibilityLabel("Закрыть \(tab.title)")
                .onHover { hovering in
                    if hovering { hoveredTabCloseID = tab.id }
                    else if hoveredTabCloseID == tab.id { hoveredTabCloseID = nil }
                }
                .onDisappear { if hoveredTabCloseID == tab.id { hoveredTabCloseID = nil } }
            }
        }
        .contentShape(Rectangle())
        .background(background, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            if hovering {
                hoveredTabID = tab.id
            } else if hoveredTabID == tab.id {
                hoveredTabID = nil
            }
        }
        .onDisappear { if hoveredTabID == tab.id { hoveredTabID = nil } }
        .contextMenu { tabActions(tab) }
        .modifier(TabStripDragItem(
            offset: tabReorder?.offset(for: tab.id, origin: tabContentFrame.minX, spacing: TabStripMetrics.spacing,
                                      viewport: tabViewportFrame) ?? 0,
            active: tabReorder?.item == tab.id,
            measure: { tabFrames[tab.id] = $0 }
        ))
        .modifier(TabRestoreAppearance(restored: browser.reopenedTabID == tab.id, reduceMotion: reduceMotion))
    }

    @ViewBuilder private func tabActions(_ tab: Tab) -> some View {
        Button("Новая вкладка") {
            browser.newTab(SavedTab(group: tab.saved.group),
                           at: browser.tabs.firstIndex(where: { $0 === tab }).map { $0 + 1 })
        }
        Menu("Перенести вкладку") {
            Button("В новую группу…") {
                editGroup()
                tabForNewGroup = tab
            }
            Button("Без группы") { browser.move(tab, to: nil) }
                .disabled(tab.saved.group == nil)
            ForEach(browser.data.groups, id: \.self) { group in
                Button(group) { browser.move(tab, to: group) }
                    .disabled(tab.saved.group == group)
            }
        }
        Divider()
        Button("Обновить") { browser.reload(tab) }
            .disabled(tab.view == nil)
        Button("Обновить все открытые вкладки") { browser.reloadAll() }
        Button("Дублировать") { browser.duplicate(tab) }
        Button(tab.saved.pinned ? "Открепить вкладку" : "Закрепить вкладку") { browser.togglePin(tab) }
        Button(tab.saved.muted == true ? "Включить звук на вкладке" : "Отключить звук на вкладке") {
            browser.toggleMute(tab)
        }
        Divider()
        Button("Закрыть вкладку") { browser.close(tab) }
        Button("Закрыть другие вкладки") { browser.closeTabs(relativeTo: tab, scope: .others) }
            .disabled(browser.tabsToClose(relativeTo: tab, scope: .others).isEmpty)
        Button("Закрыть вкладки слева") { browser.closeTabs(relativeTo: tab, scope: .left) }
            .disabled(browser.tabsToClose(relativeTo: tab, scope: .left).isEmpty)
        Button("Закрыть вкладки справа") { browser.closeTabs(relativeTo: tab, scope: .right) }
            .disabled(browser.tabsToClose(relativeTo: tab, scope: .right).isEmpty)
        Divider()
        Button("Открыть закрытую вкладку") { browser.reopen() }
            .disabled(browser.data.closed.isEmpty)
        Button("Настройки") { browser.show(.settings) }
    }

    private func scrollWhileDragging<ID>(_ value: () -> TabStripReorder<ID>?, content: () -> CGRect,
                                          viewport: () -> CGRect, spacing: CGFloat, scroll: ScrollViewProxy) async {
        let direction = value()?.scrollDirection(in: viewport()) ?? 0
        guard direction != 0 else { return }
        while !Task.isCancelled, let drag = value(), drag.scrollDirection(in: viewport()) == direction,
              let target = drag.scrollTarget(origin: content().minX, spacing: spacing,
                                             viewport: viewport(), forward: direction > 0) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                scroll.scrollTo(target, anchor: direction > 0 ? .trailing : .leading)
            }
            do { try await Task.sleep(for: .milliseconds(180)) }
            catch { return }
        }
    }

    private var groupReorderGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($reorderingStrip) { _, active, _ in active = true }
            .onChanged { value in
                if groupReorder == nil {
                    guard let group = browser.data.groups.first(where: {
                        groupFrames[$0]?.contains(value.startLocation) == true
                    }) else { return }
                    groupReorder = TabStripReorder(item: group, order: browser.data.groups, frames: groupFrames)
                }
                groupReorder?.update(translation: value.translation.width, location: value.location,
                                     origin: groupContentFrame.minX, spacing: 4, viewport: groupViewportFrame)
            }
            .onEnded { value in
                guard let drag = groupReorder else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    groupReorder = nil
                    let order = drag.arranged(browser.data.groups)
                    if groupViewportFrame.contains(value.location), let index = order.firstIndex(of: drag.item),
                       browser.data.groups.indices.contains(index) {
                        browser.reorderGroup(drag.item, at: browser.data.groups[index])
                    }
                }
            }
    }

    private var tabReorderGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($reorderingStrip) { _, active, _ in active = true }
            .onChanged { value in
                if tabReorder == nil {
                    guard let tab = browser.visibleTabs.first(where: {
                        tabFrames[$0.id]?.contains(value.startLocation) == true
                    }) else { return }
                    tabReorder = TabStripReorder(item: tab.id, order: browser.visibleTabs.map(\.id), frames: tabFrames)
                }
                tabReorder?.update(translation: value.translation.width, location: value.location,
                                   origin: tabContentFrame.minX, spacing: TabStripMetrics.spacing, viewport: tabViewportFrame)
            }
            .onEnded { value in
                guard let drag = tabReorder, let tab = browser.tabs.first(where: { $0.id == drag.item }) else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    tabReorder = nil
                    if groupViewportFrame.contains(value.location),
                       let group = browser.data.groups.first(where: { groupFrames[$0]?.contains(value.location) == true }) {
                        browser.move(tab, to: group)
                    } else if tabViewportFrame.contains(value.location) {
                        let tabs = browser.visibleTabs
                        let order = drag.arranged(tabs.map(\.id))
                        if let index = order.firstIndex(of: tab.id), tabs.indices.contains(index) {
                            browser.reorder(tab, at: tabs[index])
                        }
                    }
                }
            }
    }

    private func editGroup(_ group: String? = nil) {
        groupToRename = group
        tabForNewGroup = nil
        groupName = group ?? ""
        groupDialog = true
    }

    private var content: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let page = browser.active?.saved.internalPage {
                GeometryReader { geometry in
                    let scale = CGFloat(browser.pageZoomPercent) / 100
                    let size = geometry.size
                    internalContent(page)
                        .frame(width: size.width / scale, height: size.height / scale)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                }
                .clipped()
            } else if let error = browser.active?.error {
                ContentUnavailableView {
                    Label("Страница не открылась", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Повторить") { browser.reload() }
                }
            } else if let web = browser.active?.view {
                WebSurface(web: web).id(browser.activeID)
            } else {
                startPage
            }
        }
    }

    private var startPage: some View {
        VStack(spacing: 24) {
            Text(browser.isPrivate ? "Инкогнито" : "myBro")
                .font(.system(size: 32, weight: .semibold))
            if startClock {
                TimelineView(.everyMinute) { clock in
                    Text(clock.date, format: .dateTime.hour().minute())
                        .font(.system(size: 42, weight: .medium))
                        .monospacedDigit()
                }
            }
            if startSearch { addressBox(isStart: true) }
            if startTiles, !browser.isPrivate, !browser.data.bookmarks.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Array(browser.data.bookmarks.prefix(8)), id: \.url) { page in
                        Button {
                            startFocused = false
                            browser.open(page)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "globe").font(.title2).foregroundStyle(.secondary)
                                Text(page.title).font(.caption).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 66)
                            .background(.background, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .help(page.url.absoluteString)
                    }
                }
            }
        }
        .frame(maxWidth: 520)
        .padding(24)
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            TextField("Найти на странице", text: $findText)
                .textFieldStyle(.roundedBorder)
                .focused($findFocused)
                .onSubmit { find() }
            Text(findStatus).font(.caption)
            icon("chevron.up", "Предыдущее совпадение") { find(backwards: true) }
            icon("chevron.down", "Следующее совпадение") { find() }
            icon("xmark", "Закрыть поиск") { findVisible = false }.keyboardShortcut(.escape, modifiers: [])
        }
        .padding(8)
        .background(.bar)
    }

    private var notesSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Заметки").font(.title2.weight(.semibold))
                Spacer()
                Button("Готово") { showsNotes = false }.keyboardShortcut(.cancelAction)
            }
            TextEditor(text: $notes).accessibilityLabel("Заметки")
        }
        .padding(16)
        .frame(width: 560, height: 460)
    }

    @ViewBuilder
    private func internalContent(_ page: InternalPage) -> some View {
        switch page {
        case .history:
            let grouped = historyGrouped
            let days = grouped.keys.sorted { ($0 ?? .distantPast) > ($1 ?? .distantPast) }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("История").font(.title2.weight(.semibold))
                    Spacer()
                    clearPeriodPicker
                    Button("Очистить историю", role: .destructive) {
                        browser.clearHistory(clearPeriod)
                        selectedVisits.removeAll()
                    }
                        .disabled(browser.data.history.isEmpty && browser.data.closed.isEmpty)
                    clearCookiesButton
                }
                if cookiesCleared { Text("Cookies удалены").foregroundStyle(.secondary) }
                if !selectedVisits.isEmpty {
                    Button("Удалить выбранное (\(selectedVisits.count))", role: .destructive) {
                        browser.deleteVisits(selectedVisits)
                        selectedVisits.removeAll()
                    }
                }
                if browser.data.history.isEmpty {
                    Text("История пока пуста.").foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List {
                        ForEach(days, id: \.self) { day in
                            Section {
                                ForEach(grouped[day] ?? []) { visit in
                                    historyRow(visit)
                                }
                            } header: {
                                historyDayDivider(day)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: 860, maxHeight: .infinity, alignment: .topLeading)
        case .settings:
            BrowserSettingsPage(browser: browser, engine: engine, searchEnabled: search,
                                suggestionsEnabled: networkSuggestions, showHistory: showHistory)
        case .bookmarks:
            BookmarkManager(browser: browser)
        case .downloads:
            DownloadHistoryPage(downloads: browser.downloads, isPrivate: browser.isPrivate) {
                browser.show($0)
            }
        case .passwords:
            PasswordManager(browser: browser)
        case .profile:
            ProfileTransferView(browser: browser)
        case .extensions:
            BrowserExtensionsPage()
        }
    }

    private var historyGrouped: [Date?: [HistoryVisit]] {
        Dictionary(grouping: browser.data.history) { visit in
            visit.visitedAt.map { Calendar.current.startOfDay(for: $0) }
        }
    }

    private func historyDayTitle(_ day: Date?) -> String {
        guard let day else { return "Дата неизвестна" }
        if Calendar.current.isDateInToday(day) { return "Сегодня" }
        if Calendar.current.isDateInYesterday(day) { return "Вчера" }
        return day.formatted(date: .long, time: .omitted)
    }

    private func historyDayDivider(_ day: Date?) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(.separator).frame(height: 1)
            Text(historyDayTitle(day))
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(.separator).frame(height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .textCase(nil)
    }

    private func historyRow(_ visit: HistoryVisit) -> some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { selectedVisits.contains(visit.id) }, set: { selected in
                if selected { selectedVisits.insert(visit.id) } else { selectedVisits.remove(visit.id) }
            })) { Text("Выбрать \(visit.title)") }
                .labelsHidden()
                .toggleStyle(.checkbox)
            if let time = visit.visitedAt {
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .frame(minWidth: 64, alignment: .leading)
            }
            Button {
                browser.newTab(SavedTab(page: visit.page, group: browser.activeGroup))
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(visit.title).lineLimit(1)
                    Text(visit.url.absoluteString)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var clearPeriodPicker: some View {
        Picker("Период", selection: $clearPeriod) {
            ForEach(ClearPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .fixedSize()
        .onChange(of: clearPeriod) { cookiesCleared = false }
    }

    private var clearCookiesButton: some View {
        Button(clearingCookies ? "Удаление…" : "Удалить cookies", role: .destructive) {
            clearingCookies = true
            cookiesCleared = false
            Task {
                await browser.clearCookies(clearPeriod)
                clearingCookies = false
                cookiesCleared = true
            }
        }
        .disabled(clearingCookies)
    }

    private func icon(_ symbol: String, _ label: String, inAddressToolbar: Bool = false,
                      action: @escaping () -> Void) -> some View {
        let size = inAddressToolbar ? AddressToolbarMetrics.controlSize : 24
        return Button(action: action) {
            Label(label, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(inAddressToolbar ? .system(size: AddressToolbarMetrics.symbolSize) : nil)
                .frame(minWidth: size, minHeight: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }

    private func syncAddress() {
        if let page = browser.active?.saved.internalPage {
            address = "mybro://\(page.rawValue)"
        } else {
            address = browser.active?.saved.localFile?.absoluteString ?? browser.active?.saved.page?.url.absoluteString ?? ""
        }
        inputError = false
        editingAddress = false
        suggestionIndex = nil
    }

    private func showHistory() {
        cookiesCleared = false
        selectedVisits.removeAll()
        browser.show(.history)
    }

    private func focusAddress() {
        addressFocused = true
        addressFocusRequest += 1
    }

    private func focusStart() {
        guard startSearch else { focusAddress(); return }
        startFocused = true
        startFocusRequest += 1
    }

    private func handleAddressCommand(_ command: Selector) -> Bool {
        switch NSStringFromSelector(command) {
        case "moveDown:": return stepSuggestion(1)
        case "moveUp:": return stepSuggestion(-1)
        case "cancelOperation:" where editingAddress:
            editingAddress = false
            return true
        case "insertNewline:":
            submitAddress()
            return true
        default: return false
        }
    }

    private func stepSuggestion(_ offset: Int) -> Bool {
        let count = addressSuggestions.count
        guard count > 0 else { return false }
        let previous = suggestionIndex ?? 0
        suggestionIndex = min(count - 1, max(0, previous + offset))
        return true
    }

    private func submitAddress() {
        let suggestions = addressSuggestions
        let index = suggestionIndex ?? 0
        if suggestions.indices.contains(index) {
            submitSuggestion(suggestions[index])
        } else {
            submit()
        }
    }

    private func submitSuggestion(_ suggestion: AddressSuggestion) {
        switch suggestion {
        case let .site(page):
            if let tab = openTab(for: page) {
                endAddressEditing()
                browser.select(tab)
            } else {
                submit(url: page.url)
            }
        case let .search(query):
            submit(url: engine.wrappedValue.searchURL(query))
        }
    }

    private func endAddressEditing() {
        inputError = false
        editingAddress = false
        suggestionIndex = nil
        addressFocused = false
        startFocused = false
    }

    private func submit(url candidate: URL? = nil) {
        if candidate == nil, address.hasPrefix("mybro://"),
           let page = InternalPage(rawValue: String(address.dropFirst("mybro://".count))),
           !browser.isPrivate || page.availableInPrivate {
            endAddressEditing()
            browser.show(page)
            return
        }
        guard let url = candidate ?? Address.resolve(address, search: search.wrappedValue, engine: engine.wrappedValue) else {
            inputError = true
            return
        }
        endAddressEditing()
        browser.open(url)
    }

    private func zoom(_ action: PageZoomAction) -> Bool {
        guard browser.changePageZoom(action) else { return false }
        zoomFeedback = UUID()
        return true
    }

    private func find(backwards: Bool = false) {
        guard !findText.isEmpty, let web = browser.active?.view else { return }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.wraps = true
        web.find(findText, configuration: config) { result in
            findStatus = result.matchFound ? "" : "Совпадений нет"
        }
    }

    private func printPage() {
        guard let web = browser.active?.view, let window = web.window else { return }
        let operation = web.printOperation(with: NSPrintInfo.shared)
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    private func takeSnapshot() {
        guard allowsPageSnapshots, let web = browser.active?.view else { return }
        web.takeSnapshot(with: nil) { image, error in
            guard let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                snapshotError = error?.localizedDescription ?? "Не удалось получить изображение страницы."
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "myBro.png"
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try png.write(to: url, options: .atomic)
                } catch {
                    snapshotError = error.localizedDescription
                }
            }
        }
    }
}

private extension GroupTint {
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .gray: .gray
        }
    }
}

private struct PrivateWindowMarker: NSViewRepresentable {
    final class View: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isRestorable = false
        }
    }

    func makeNSView(context: Context) -> View { View() }
    func updateNSView(_ view: View, context: Context) {}
}

struct WebSurface: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
