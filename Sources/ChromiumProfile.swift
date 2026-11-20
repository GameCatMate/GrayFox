import Foundation
import SQLite3

struct ChromiumProfile {
    enum Source: String, CaseIterable, Identifiable {
        case vivaldi = "Vivaldi"
        case yandex = "Яндекс Браузер"
        case chromium = "Другой Chromium"
        var id: Self { self }

        var defaultFolder: URL {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            switch self {
            case .vivaldi: return support.appending(path: "Vivaldi")
            case .yandex: return support.appending(path: "Yandex/YandexBrowser")
            case .chromium: return support
            }
        }
    }

    var contents: ProfileContents
    var skipped: [String]

    private struct BookmarkFile: Decodable {
        let roots: [String: Bookmark]
    }

    private struct Bookmark: Decodable {
        let type: String?
        let name: String?
        let url: String?
        let children: [Bookmark]?

        var title: String { name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

        func append(to folders: inout [BookmarkFolder], parent: UUID?, depth: Int = 0) {
            guard depth < 64, let children else { return }
            var folder = BookmarkFolder(name: title.isEmpty ? "Закладки" : title, parentID: parent)
            folder.pages = children.compactMap {
                guard $0.type == "url", let text = $0.url, let url = URL(string: text), Address.isWeb(url) else { return nil }
                return Page(title: $0.title.isEmpty ? (url.host ?? text) : $0.title, url: url)
            }
            folders.append(folder)
            for node in children where node.type == "folder" {
                node.append(to: &folders, parent: folder.id, depth: depth + 1)
            }
        }
    }

    static func read(directory: URL, source: Source, readSavedTabs: Bool = true) throws -> ChromiumProfile {
        let defaultProfile = directory.appending(path: "Default")
        let files = FileManager.default
        let hasProfileFiles = ["Bookmarks", "History", "Preferences", "Sessions", "Sessions_Encrypted"].contains {
            files.fileExists(atPath: directory.appending(path: $0).path)
        }
        let folder = hasProfileFiles ||
            !files.fileExists(atPath: defaultProfile.path) ? directory : defaultProfile
        var contents = ProfileContents()
        var skipped: [String] = []
        var recognized = false
        let preferencesFile = folder.appending(path: "Preferences")
        let preferenceData = try? ProfileArchive.read(preferencesFile, limit: 16 * 1024 * 1024)
        let workspaceNames = source == .vivaldi ? vivaldiWorkspaces(preferenceData) : nil

        let bookmarks = folder.appending(path: "Bookmarks")
        if files.fileExists(atPath: bookmarks.path) {
            do {
                let bytes = try ProfileArchive.read(bookmarks, limit: 32 * 1024 * 1024)
                let tree = try JSONDecoder().decode(BookmarkFile.self, from: bytes)
                let root = BookmarkFolder(name: source.rawValue)
                var folders = [root]
                let common = ["bookmark_bar", "other", "synced"]
                let keys = common + tree.roots.keys.filter { !common.contains($0) }.sorted()
                for key in keys where key != "trash" {
                    tree.roots[key]?.append(to: &folders, parent: root.id)
                }
                contents.browser.bookmarkFolders = folders.count > 1 ? folders : nil
                recognized = true
            } catch { skipped.append("закладки") }
        }

        let history = folder.appending(path: "History")
        if files.fileExists(atPath: history.path) {
            do {
                (contents.browser.history, contents.downloads) = try readHistory(history)
                recognized = true
            } catch { skipped.append("история") }
        }

        if readSavedTabs {
            var loaded = false
            let candidates = sessionFiles(in: folder)
            for (index, session) in candidates.prefix(8).enumerated() {
                guard let bytes = try? ProfileArchive.read(session, limit: 64 * 1024 * 1024),
                      let tabs = try? ChromiumSession.read(bytes, defaultGroup: source.rawValue,
                                                           workspaceNames: workspaceNames) else { continue }
                contents.browser.tabs = tabs.tabs
                contents.browser.groups = tabs.groups
                contents.browser.groupTints = tabs.tints
                if index > 0 { skipped.append("последняя сессия вкладок, использована более ранняя") }
                recognized = true
                loaded = true
                break
            }
            if !loaded {
                if files.fileExists(atPath: folder.appending(path: "Sessions_Encrypted").path) {
                    skipped.append("открытые вкладки (зашифрованная сессия)")
                } else {
                    skipped.append(candidates.isEmpty ? "открытые вкладки (файл сессии не найден)" : "открытые вкладки")
                }
            }
        }

        if let data = preferenceData,
           let tree = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let provider = (tree["default_search_provider_data"] as? [String: Any])?["template_url_data"] as? [String: Any]
            let name = (provider?["short_name"] as? String)?.lowercased()
            let known = SearchEngine.allCases.first { $0.rawValue.lowercased() == name }
            if let known { contents.preferences["address-search-engine"] = known.rawValue }
        }

        guard recognized else { throw ProfileError.invalidFile }
        return ChromiumProfile(contents: contents, skipped: skipped)
    }

    private static func vivaldiWorkspaces(_ data: Data?) -> [Int64: String] {
        struct Preferences: Decodable {
            struct Vivaldi: Decodable {
                struct Workspaces: Decodable {
                    struct Workspace: Decodable {
                        let id: Int64
                        let name: String
                    }
                    let list: [Workspace]?
                }
                let workspaces: Workspaces?
            }
            let vivaldi: Vivaldi?
        }
        guard let data, let settings = try? JSONDecoder().decode(Preferences.self, from: data) else { return [:] }
        var names: [Int64: String] = [:]
        for item in settings.vivaldi?.workspaces?.list ?? [] {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { names[item.id] = name }
        }
        return names
    }

    private static func sessionFiles(in folder: URL) -> [URL] {
        let files = FileManager.default
        let directory = folder.appending(path: "Sessions")
        let sessions = (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let ranked = sessions.compactMap { url -> (URL, UInt64)? in
            let name = url.lastPathComponent
            guard name.hasPrefix("Session_"), let stamp = UInt64(name.dropFirst("Session_".count)) else { return nil }
            return (url, stamp)
        }
        return ranked.sorted(by: { $0.1 > $1.1 }).map(\.0) +
            ["Current Session", "Last Session"].map { folder.appending(path: $0) }
            .filter { files.fileExists(atPath: $0.path) }
    }

    private static func readHistory(_ url: URL) throws -> ([HistoryVisit], [DownloadItem]) {
        var db: OpaquePointer?
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else {
            throw ProfileError.invalidHistory
        }
        let status = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(db) }
        guard status == SQLITE_OK else { throw ProfileError.invalidHistory }
        sqlite3_exec(db, "PRAGMA trusted_schema = OFF", nil, nil, nil)
        sqlite3_busy_timeout(db, 1500)

        var visits: [HistoryVisit] = []
        try rows(db, sql: """
            SELECT urls.url, urls.title, visits.visit_time FROM visits
            JOIN urls ON urls.id = visits.url ORDER BY visits.visit_time DESC
            """) { row in
                guard let raw = sqliteText(row, 0), let address = URL(string: raw), Address.isWeb(address),
                      let date = fromChromiumTime(sqlite3_column_int64(row, 2)) else { return }
                let page = Page(title: sqliteText(row, 1).flatMap { $0.isEmpty ? nil : $0 } ?? address.host ?? raw,
                                url: address)
                visits.append(HistoryVisit(page: page, at: date))
            }

        var downloads: [DownloadItem] = []
        try? rows(db, sql: """
            SELECT downloads.target_path, downloads.start_time, downloads.state, downloads_url_chains.url
            FROM downloads LEFT JOIN downloads_url_chains
            ON downloads_url_chains.id = downloads.id AND downloads_url_chains.chain_index = 0
            ORDER BY downloads.start_time DESC
            """) { row in
                guard let path = sqliteText(row, 0), !path.isEmpty,
                      let date = fromChromiumTime(sqlite3_column_int64(row, 1)) else { return }
                let source = DownloadItem.historySource(sqliteText(row, 3).flatMap(URL.init(string:)))
                let name = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? "Загрузка"
                let state: DownloadItem.State = sqlite3_column_int(row, 2) == 1
                    ? .complete : .failed("Загрузка не завершена")
                downloads.append(DownloadItem(name: name, destination: nil, sourceURL: source, startedAt: date, state: state))
            }
        return (visits, downloads)
    }

    private static func rows(_ db: OpaquePointer?, sql: String, handle: (OpaquePointer?) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ProfileError.invalidHistory }
        defer { sqlite3_finalize(statement) }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: handle(statement)
            case SQLITE_DONE: return
            default: throw ProfileError.invalidHistory
            }
        }
    }

    private static func sqliteText(_ row: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(row, column).map { String(cString: $0) }
    }

    private static func fromChromiumTime(_ microseconds: Int64) -> Date? {
        guard microseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(microseconds) / 1_000_000 - 11_644_473_600)
    }
}
