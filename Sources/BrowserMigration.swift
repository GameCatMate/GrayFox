import Foundation

struct BrowserMigration {
    struct Inputs {
        var source: ChromiumProfile.Source
        var directory: URL?
        var tabsFile: URL?
        var passwordsFile: URL?

        var isEmpty: Bool { directory == nil && tabsFile == nil && passwordsFile == nil }

        static func launchArguments(_ arguments: [String]) throws -> Inputs? {
            guard let start = arguments.firstIndex(of: "--mybro-import") else { return nil }
            let fields = Array(arguments.dropFirst(start + 1))
            guard fields.count == 3, let source = ChromiumProfile.Source(rawValue: fields[0]),
                  fields[1].hasPrefix("/"), fields[2].hasPrefix("/") else { throw ProfileError.invalidFile }
            return Inputs(source: source, directory: URL(fileURLWithPath: fields[1], isDirectory: true),
                          passwordsFile: URL(fileURLWithPath: fields[2]))
        }
    }

    var contents: ProfileContents
    var warnings: [String]

    var counts: ProfileImportResult {
        ProfileImportResult(
            bookmarks: contents.browser.bookmarks.count
                + (contents.browser.bookmarkFolders ?? []).reduce(0) { $0 + $1.pages.count },
            visits: contents.browser.history.count,
            tabs: contents.browser.tabs.count,
            passwords: contents.passwords.count,
            downloads: contents.downloads.count
        )
    }

    static func inspect(_ inputs: Inputs) throws -> BrowserMigration {
        guard !inputs.isEmpty else { throw ProfileError.invalidFile }
        var contents = ProfileContents()
        var warnings: [String] = []

        if let directory = inputs.directory {
            let profile = try ChromiumProfile.read(directory: directory, source: inputs.source,
                                                   readSavedTabs: inputs.tabsFile == nil)
            contents = profile.contents
            if !profile.skipped.isEmpty {
                warnings.append("Из папки профиля не прочитано: \(profile.skipped.joined(separator: ", ")).")
            }
            if inputs.tabsFile == nil, !contents.browser.tabs.isEmpty {
                warnings.append("Вкладки взяты из последней читаемой сохранённой сессии. Открытые после её записи вкладки могут отсутствовать.")
            }
        }

        if let file = inputs.tabsFile {
            let data = try ProfileArchive.read(file, limit: 64 * 1024 * 1024)
            if data.starts(with: Data("SNSS".utf8)) {
                let tabs = try ChromiumSession.read(data, defaultGroup: inputs.source.rawValue)
                contents.browser.tabs = tabs.tabs
                contents.browser.groups = tabs.groups
                contents.browser.groupTints = tabs.tints
                warnings.append("Используется выбранная сохранённая сессия.")
            } else {
                let live = try OpenTabsExport.read(data, source: inputs.source)
                contents.browser.tabs = live.tabs
                contents.browser.groups = live.groups
                contents.browser.groupTints = live.tints
                if live.skipped > 0 { warnings.append("Пропущено неподдерживаемых вкладок: \(live.skipped).") }
            }
            if contents.browser.tabs.isEmpty { warnings.append("В выбранном файле нет поддерживаемых вкладок.") }
        }

        if let file = inputs.passwordsFile {
            let imported = try PasswordImport.decode(ProfileArchive.read(file, limit: 16 * 1024 * 1024))
            contents.passwords = imported.entries
            if imported.skipped > 0 {
                warnings.append("Пропущено записей паролей: \(imported.skipped). Требуются адрес HTTP/HTTPS и непустой пароль.")
            }
            if contents.passwords.contains(where: { $0.origin.url.scheme == "http" }) {
                warnings.append("Пароли для HTTP сохранены в менеджере. Автозаполнение выполняется на HTTPS.")
            }
        }
        identifyGroups(in: &contents.browser, source: inputs.source)
        return BrowserMigration(contents: contents, warnings: warnings)
    }

    private static func identifyGroups(in browser: inout BrowserData, source: ChromiumProfile.Source) {
        let prefix = source.rawValue + " · "
        var names: [String: String] = [:]
        var used: Set<String> = []
        var tints: [String: GroupTint] = [:]
        for group in browser.groups {
            let base = group == source.rawValue || group.hasPrefix(prefix) ? group : prefix + group
            var name = base
            var suffix = 2
            while !used.insert(name).inserted {
                name = "\(base) (\(suffix))"
                suffix += 1
            }
            names[group] = name
            tints[name] = browser.groupTints?[group]
        }
        browser.groups = browser.groups.compactMap { names[$0] }
        browser.groupTints = tints
        for index in browser.tabs.indices {
            if let group = browser.tabs[index].group { browser.tabs[index].group = names[group] }
        }
    }
}

private struct OpenTabsExport: Decodable {
    struct Group: Decodable {
        let id: Int
        let window: Int
        let title: String
        let color: String
    }

    struct Tab: Decodable {
        let window: Int
        let index: Int
        let group: Int?
        let pinned: Bool
        let title: String
        let url: String
    }

    private struct GroupIdentity: Hashable {
        let window: Int
        let id: Int
    }

    let version: Int
    let groups: [Group]
    let tabs: [Tab]
    let skipped: Int

    static func read(_ data: Data, source: ChromiumProfile.Source) throws
        -> (tabs: [SavedTab], groups: [String], tints: [String: GroupTint], skipped: Int) {
        let export = try JSONDecoder().decode(OpenTabsExport.self, from: data)
        guard export.version == 1, (0...100_000).contains(export.skipped),
              export.tabs.count <= 100_000, export.groups.count <= 100_000 else { throw ProfileError.invalidFile }

        var saved: [SavedTab] = []
        var names: [String] = []
        var tints: [String: GroupTint] = [:]
        var used: Set<String> = []
        var existingNames: [GroupIdentity: String] = [:]
        var groupDetails: [GroupIdentity: Group] = [:]
        for group in export.groups { groupDetails[GroupIdentity(window: group.window, id: group.id)] = group }
        let windows = Set(export.tabs.map(\.window)).sorted()
        let windowNumbers = Dictionary(uniqueKeysWithValues: windows.enumerated().map { ($0.element, $0.offset + 1) })
        var skipped = export.skipped

        for tab in export.tabs.sorted(by: { ($0.window, $0.index) < ($1.window, $1.index) }) {
            guard tab.window >= 0, tab.index >= 0, let url = URL(string: tab.url), Address.isWeb(url) else {
                skipped += 1
                continue
            }
            let groupID = GroupIdentity(window: tab.window, id: max(-1, tab.group ?? -1))
            let name: String
            if let known = existingNames[groupID] {
                name = known
            } else {
                let details = groupDetails[groupID]
                let title = details?.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let base: String
                if groupID.id < 0 {
                    base = windows.count > 1 ? "\(source.rawValue) · Окно \(windowNumbers[tab.window] ?? 1)" : source.rawValue
                } else {
                    base = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Группа"
                }
                var unique = base
                var suffix = 2
                while !used.insert(unique).inserted {
                    unique = "\(base) (\(suffix))"
                    suffix += 1
                }
                name = unique
                existingNames[groupID] = unique
                names.append(unique)
                if let details { tints[unique] = tint(details.color) }
            }
            let title = tab.title.isEmpty ? (url.host ?? tab.url) : tab.title
            saved.append(SavedTab(page: Page(title: title, url: url), group: name, pinned: tab.pinned))
        }
        return (saved, names, tints, skipped)
    }

    private static func tint(_ color: String) -> GroupTint {
        switch color {
        case "grey": .gray
        case "red": .red
        case "yellow", "orange": .orange
        case "green", "cyan": .green
        case "purple", "pink": .purple
        default: .blue
        }
    }
}
