import AppKit
import SwiftUI

extension BrowserTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private enum SettingsTopic: String, CaseIterable {
    case general = "Общие настройки"
    case interface = "Интерфейс"
    case tools = "Инструменты"
    case sites = "Сайты"
    case system = "Системные"
    case accessibility = "Специальные возможности"
}

private enum SettingsGroup: String, CaseIterable {
    case profile = "Профиль"
    case search = "Поиск"
    case theme = "Цветовая схема"
    case start = "Вид экрана новой вкладки"
    case tabs = "Вкладки и группы"
    case bookmarks = "Панель закладок"
    case autofill = "Автозаполнение"
    case downloads = "Загруженные файлы"
    case screenshots = "Скриншоты"
    case files = "Просмотр файлов"
    case extensions = "Расширения"
    case permissions = "Разрешения сайтов"
    case zoom = "Масштаб страниц"
    case network = "Сеть"
    case privacy = "Конфиденциальность"
    case reset = "Сброс настроек"
    case accessibility = "Доступ к контенту"

    var topic: SettingsTopic {
        switch self {
        case .profile, .search: .general
        case .theme, .start, .tabs, .bookmarks: .interface
        case .autofill, .downloads, .screenshots, .files, .extensions: .tools
        case .permissions, .zoom: .sites
        case .network, .privacy, .reset: .system
        case .accessibility: .accessibility
        }
    }

    var keywords: String {
        switch self {
        case .profile: "импорт экспорт данные перенос профиль"
        case .search: "поисковая система запрос адресная строка подсказки google duckduckgo"
        case .theme: "тема цвет светлая тёмная системная"
        case .start: "часы табло поисковая строка"
        case .tabs: "восстанавливать при запуске новая вкладка группы ширина дублировать внешние ссылки"
        case .bookmarks: "закладки избранное показывать скрыть значки сайтов"
        case .autofill: "менеджер паролей логин сохранённые пароли"
        case .downloads: "загрузки загрузок папка папку сохранять файлы спрашивать"
        case .screenshots: "снимок изображения страницы"
        case .files: "pdf документы открывать в браузере"
        case .extensions: "блокировка рекламы ublock manifest v2 v3 chromium"
        case .permissions: "камера микрофон запрос доступ"
        case .zoom: "увеличение уменьшение масштаб сайты"
        case .network: "https безопасность протокол"
        case .privacy: "очистить история удалить cookies куки час день неделя год"
        case .reset: "сбросить вернуть настройки по умолчанию"
        case .accessibility: "размер шрифта текст уменьшить анимацию"
        }
    }

    var visibleInPrivate: Bool {
        self != .profile && self != .bookmarks && self != .autofill && self != .extensions && self != .reset
    }

    func matches(_ query: String) -> Bool {
        let searchable = "\(topic.rawValue) \(rawValue) \(keywords)"
        return query.split(whereSeparator: \.isWhitespace).allSatisfy {
            searchable.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

private struct SettingsSectionOffsets: PreferenceKey {
    static let defaultValue: [SettingsTopic: CGFloat] = [:]

    static func reduce(value: inout [SettingsTopic: CGFloat], nextValue: () -> [SettingsTopic: CGFloat]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

struct BrowserSettingsPage: View {
    @ObservedObject var browser: Browser
    @Binding var engine: SearchEngine
    @Binding var searchEnabled: Bool
    @Binding var suggestionsEnabled: Bool
    let showHistory: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(BrowserPreference.theme) private var theme: BrowserTheme = .system
    @AppStorage(BrowserPreference.startSearch) private var startSearch = true
    @AppStorage(BrowserPreference.startTiles) private var startTiles = true
    @AppStorage(BrowserPreference.startClock) private var startClock = false
    @AppStorage(BrowserPreference.bookmarkBar) private var bookmarkBar: BookmarkBarVisibility = .always
    @AppStorage(BrowserPreference.bookmarkIcons) private var bookmarkIcons = true
    @AppStorage(BrowserPreference.restoreTabs) private var restoreTabs = true
    @AppStorage(BrowserPreference.extraStartTab) private var extraStartTab = false
    @AppStorage(BrowserPreference.reuseExternalTab) private var reuseExternalTab = false
    @AppStorage(BrowserPreference.pageZoom) private var pageZoom = 100
    @AppStorage(BrowserPreference.minimumFontSize) private var minimumFont = 0
    @AppStorage(BrowserPreference.previewPDF) private var previewPDF = true
    @AppStorage(BrowserPreference.allowCamera) private var allowCamera = true
    @AppStorage(BrowserPreference.allowMicrophone) private var allowMicrophone = true
    @AppStorage(BrowserPreference.pageSnapshots) private var pageSnapshots = true
    @AppStorage(BrowserPreference.reduceMotion) private var reduceMotion = false
    @AppStorage(BrowserPreference.downloadsFolder) private var downloadsFolder = ""
    @AppStorage(BrowserPreference.askDownloadFolder) private var askDownloadFolder = false
    @AppStorage(PasswordForms.autofillKey) private var passwordAutofill = true

    @State private var query = ""
    @State private var selected: SettingsTopic = .general
    @State private var period: ClearPeriod = .hour
    @State private var isClearing = false
    @State private var confirmsHistory = false
    @State private var confirmsReset = false
    @State private var feedback: String?
    @State private var defaultBrowser = true
    @State private var defaultBrowserError: String?
    @State private var settingDefaultBrowser = false

    private var card: Color {
        colorScheme == .dark ? Color(white: 0.09) : Color(nsColor: .windowBackgroundColor)
    }

    var body: some View {
        let all = SettingsGroup.allCases.filter { !browser.isPrivate || $0.visibleInPrivate }
        let groups = all.filter { $0.matches(query) }
        let topics = SettingsTopic.allCases.filter { topic in groups.contains { $0.topic == topic } }

        ScrollViewReader { scroll in
            VStack(spacing: 16) {
                navigation { jump(to: .system, using: scroll) }
                HStack(alignment: .top, spacing: 8) {
                    sidebar(topics, scroll: scroll)
                    ScrollView {
                        VStack(spacing: 8) {
                            if !browser.isPrivate && !defaultBrowser && query.trimmingCharacters(in: .whitespaces).isEmpty {
                                defaultBrowserCard
                            }
                            if topics.isEmpty {
                                ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass")
                                    .frame(maxWidth: .infinity)
                            }
                            ForEach(topics, id: \.self) { topic in
                                section(topic, groups: groups.filter { $0.topic == topic })
                                    .id(topic)
                            }
                        }
                    }
                    .coordinateSpace(name: "settings-content")
                    .onPreferenceChange(SettingsSectionOffsets.self) { offsets in
                        if let current = topics.last(where: { (offsets[$0] ?? .infinity) <= 12 }) ?? topics.first {
                            selected = current
                        }
                    }
                }
            }
            .onChange(of: query) {
                if let first = topics.first { scroll.scrollTo(first, anchor: .top) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: 1030)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? .black : Color(nsColor: .underPageBackgroundColor))
        .onAppear(perform: refreshDefaultBrowser)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshDefaultBrowser()
        }
        .alert("Очистить историю?", isPresented: $confirmsHistory) {
            Button("Очистить", role: .destructive) {
                browser.clearHistory(period)
                feedback = "История очищена."
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Сбросить настройки myBro?", isPresented: $confirmsReset) {
            Button("Сбросить", role: .destructive) {
                browser.resetSettings()
                feedback = "Настройки сброшены."
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Закладки, сохранённые пароли и история останутся в профиле.")
        }
    }

    private func navigation(showSecurity: @escaping () -> Void) -> some View {
        ViewThatFits(in: .horizontal) {
            navigationItems(showSecurity: showSecurity)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity)
            ScrollView(.horizontal) {
                navigationItems(showSecurity: showSecurity)
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func navigationItems(showSecurity: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            if !browser.isPrivate {
                navButton("Мой профиль") { browser.show(.profile) }
                navButton("Закладки") { browser.show(.bookmarks) }
            }
            navButton("Загрузки") { browser.show(.downloads) }
            if !browser.isPrivate {
                navButton("История", action: showHistory)
                navButton("Расширения") { browser.show(.extensions) }
            }
            navButton("Безопасность", action: showSecurity)
            Text("Настройки")
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.primary.opacity(0.11), in: Capsule())
                .accessibilityAddTraits(.isSelected)
        }
        .font(.system(size: 13))
    }

    private func navButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).padding(.horizontal, 10).padding(.vertical, 6) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
    }

    private func sidebar(_ topics: [SettingsTopic], scroll: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Поиск", text: $query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(topics, id: \.self) { topic in
                        sidebarButton(topic) { jump(to: topic, using: scroll) }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sidebarButton(_ topic: SettingsTopic, action: @escaping () -> Void) -> some View {
        let isSelected = selected == topic
        let fill = isSelected ? Color.primary.opacity(0.12) : Color.clear
        return Button(action: action) {
            Text(topic.rawValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(fill, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func jump(to topic: SettingsTopic, using scroll: ScrollViewProxy) {
        if !SettingsGroup.allCases.contains(where: { $0.topic == topic && $0.matches(query) }) {
            query = ""
            DispatchQueue.main.async { scroll.scrollTo(topic, anchor: .top) }
        } else {
            scroll.scrollTo(topic, anchor: .top)
        }
        selected = topic
    }

    private func section(_ topic: SettingsTopic, groups: [SettingsGroup]) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(topic.rawValue)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Divider()
            ForEach(groups, id: \.self) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.rawValue).font(.body.weight(.semibold))
                    options(group)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card, in: RoundedRectangle(cornerRadius: 12))
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: SettingsSectionOffsets.self,
                                       value: [topic: geometry.frame(in: .named("settings-content")).minY])
            }
        }
    }

    @ViewBuilder
    private func options(_ group: SettingsGroup) -> some View {
        switch group {
        case .profile:
            link("Управление данными профиля") { browser.show(.profile) }
            link("Импортировать данные") { browser.show(.profile) }
        case .search:
            Picker("Поисковая система", selection: $engine) {
                ForEach(SearchEngine.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
            Toggle("Искать текст из адресной строки", isOn: $searchEnabled)
            Toggle("Показывать подсказки при наборе адресов и запросов", isOn: $suggestionsEnabled)
                .disabled(!searchEnabled)
                .help("Отправляет набираемый запрос выбранной поисковой системе.")
        case .theme:
            HStack(alignment: .top, spacing: 12) {
                ForEach(BrowserTheme.allCases, id: \.self) { option in
                    themeButton(option)
                }
            }
        case .start:
            Toggle("Часы", isOn: $startClock)
            Toggle("Поисковая строка", isOn: $startSearch)
            if !browser.isPrivate { Toggle("Табло с закладками", isOn: $startTiles) }
        case .tabs:
            Toggle("При запуске восстанавливать вкладки", isOn: $restoreTabs)
            Toggle("Дополнительно открывать новую вкладку", isOn: $extraStartTab)
                .disabled(!restoreTabs)
                .padding(.leading, 20)
            Toggle("Не дублировать вкладки при переходе из внешних приложений", isOn: $reuseExternalTab)
            Text("Минимальная ширина вкладки — 50 точек.").foregroundStyle(.secondary)
        case .bookmarks:
            Picker("Показывать панель закладок", selection: $bookmarkBar) {
                ForEach(BookmarkBarVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .fixedSize()
            Toggle("Показывать значки сайтов", isOn: $bookmarkIcons)
                .disabled(bookmarkBar == .hidden)
            link("Управление закладками") { browser.show(.bookmarks) }
        case .autofill:
            Toggle("Автоматически подставлять сохранённые пароли", isOn: $passwordAutofill)
            link("Сохранённые пароли") { browser.show(.passwords) }
        case .downloads:
            Toggle("Каждый раз спрашивать, куда сохранять файлы", isOn: $askDownloadFolder)
            Text((try? browser.downloads.destinationDirectory().path) ?? "Загрузки")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                link("Изменить папку") { chooseDownloadsFolder() }
                if !downloadsFolder.isEmpty {
                    link("Системная папка загрузок") { downloadsFolder = "" }
                }
            }
            link("История загрузок") { browser.show(.downloads) }
        case .screenshots:
            Toggle("Разрешить myBro делать снимки веб-страниц", isOn: $pageSnapshots)
        case .files:
            Toggle("Открывать PDF в браузере", isOn: $previewPDF)
        case .extensions:
            link("Менеджер расширений") { browser.show(.extensions) }
        case .permissions:
            Toggle("Разрешать сайтам запрашивать доступ к камере", isOn: $allowCamera)
            Toggle("Разрешать сайтам запрашивать доступ к микрофону", isOn: $allowMicrophone)
        case .zoom:
            Picker("Масштаб по умолчанию", selection: $pageZoom) {
                ForEach(BrowserPreference.zoomLevels, id: \.self) { Text("\($0)%").tag($0) }
            }
            .fixedSize()
        case .network:
            Text("Адреса без протокола открываются по HTTPS.")
                .foregroundStyle(.secondary)
        case .privacy:
            Picker("Период", selection: $period) {
                ForEach(ClearPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
            HStack {
                if !browser.isPrivate {
                    link("Открыть историю", action: showHistory)
                    link("Очистить историю") { confirmsHistory = true }
                        .disabled(browser.data.history.isEmpty && browser.data.closed.isEmpty)
                }
                link(isClearing ? "Удаление…" : "Удалить cookies") { clearCookies() }
                    .disabled(isClearing)
            }
            if let feedback { Text(feedback).foregroundStyle(.secondary) }
        case .reset:
            link("Сбросить настройки") { confirmsReset = true }
        case .accessibility:
            Toggle("Уменьшить анимацию интерфейса myBro", isOn: $reduceMotion)
            Picker("Минимальный размер шрифта на сайтах", selection: $minimumFont) {
                ForEach(BrowserPreference.fontSizes, id: \.self) {
                    Text($0 == 0 ? "По умолчанию" : "\($0)").tag($0)
                }
            }
            .fixedSize()
        }
    }

    private func themeButton(_ option: BrowserTheme) -> some View {
        Button {
            theme = option
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(option == .dark ? Color(white: 0.18) : Color(white: 0.94))
                    if option == .system {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(white: 0.25))
                            .mask(alignment: .leading) { Rectangle().frame(width: 29) }
                    }
                    Image(systemName: option == .system ? "circle.lefthalf.filled" : option == .dark ? "moon" : "sun.max")
                        .foregroundStyle(option == .dark ? Color.white : Color.black)
                }
                .frame(width: 58, height: 44)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme == option ? Color.accentColor : .secondary.opacity(0.3),
                                      lineWidth: theme == option ? 2 : 1)
                }
                Text(option.title).font(.caption)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(theme == option ? .isSelected : [])
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.link)
    }

    private var defaultBrowserCard: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().scaledToFit()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Сделать myBro основным браузером?").font(.body.weight(.semibold))
                Text("Ссылки из других приложений будут открываться в myBro.")
                    .foregroundStyle(.secondary)
                Button("Сделать основным", action: makeDefaultBrowser)
                    .disabled(settingDefaultBrowser)
                if let defaultBrowserError { Text(defaultBrowserError).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func refreshDefaultBrowser() {
        guard !browser.isPrivate else { return }
        let workspace = NSWorkspace.shared
        defaultBrowser = ["http", "https"].allSatisfy { scheme in
            workspace.urlForApplication(toOpen: URL(string: "\(scheme)://example.com")!)?.standardizedFileURL
                == Bundle.main.bundleURL.standardizedFileURL
        }
    }

    private func makeDefaultBrowser() {
        settingDefaultBrowser = true
        defaultBrowserError = nil
        Task { @MainActor in
            defer { settingDefaultBrowser = false; refreshDefaultBrowser() }
            do {
                for scheme in ["https", "http"] {
                    try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL,
                                                                       toOpenURLsWithScheme: scheme)
                }
            } catch { defaultBrowserError = error.localizedDescription }
        }
    }

    private func chooseDownloadsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = try? browser.downloads.destinationDirectory()
        panel.begin { result in
            if result == .OK, let url = panel.url { downloadsFolder = url.path }
        }
    }

    private func clearCookies() {
        isClearing = true
        Task {
            await browser.clearCookies(period)
            feedback = "Cookies удалены."
            isClearing = false
        }
    }
}
