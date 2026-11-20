import Foundation

struct ProfileImportResult {
    var bookmarks = 0
    var visits = 0
    var tabs = 0
    var passwords = 0
    var downloads = 0

    var message: String {
        "Добавлено: закладки — \(bookmarks), посещения — \(visits), вкладки — \(tabs), пароли — \(passwords), загрузки — \(downloads)."
    }

    private struct VisitIdentity: Hashable {
        let url: URL
        let date: Date?
        init(_ visit: HistoryVisit) {
            url = visit.url
            date = visit.visitedAt
        }
    }

    private struct TabIdentity: Hashable {
        let group: String?
        let url: URL?
        let page: InternalPage?
        let localFile: URL?
        let pinned: Bool
        init(_ tab: SavedTab) {
            group = tab.group
            url = tab.page?.url
            page = tab.internalPage
            localFile = tab.localFile
            pinned = tab.pinned
        }
    }

    static func merge(_ incoming: BrowserData, into data: inout BrowserData) -> ProfileImportResult {
        var result = ProfileImportResult()
        result.bookmarks = mergeBookmarks(incoming, into: &data)
        var visits = Set(data.history.map(VisitIdentity.init))
        var ids = Set(data.history.map(\.id))
        let newVisits = incoming.history.filter {
            Address.isWeb($0.url) && ids.insert($0.id).inserted && visits.insert(VisitIdentity($0)).inserted
        }
        data.history += newVisits
        data.history.sort { ($0.visitedAt ?? .distantPast) > ($1.visitedAt ?? .distantPast) }
        result.visits = newVisits.count

        var groups = Set(data.groups)
        var tints = data.groupTints ?? [:]
        for name in incoming.groups where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                         groups.insert(name).inserted {
            data.groups.append(name)
            tints[name] = incoming.groupTints?[name]
        }
        data.groupTints = tints

        func allowed(_ tab: SavedTab) -> Bool {
            (tab.page.map { Address.isWeb($0.url) } ?? true) &&
                (tab.localFile.map { file in
                    file.isFileURL && !file.path.isEmpty && file.user == nil && file.password == nil &&
                        (file.host == nil || file.host == "" || file.host == "localhost")
                } ?? true) &&
                (tab.group.map { groups.contains($0) } ?? true)
        }

        var existingTabs: [TabIdentity: Int] = [:]
        for tab in data.tabs { existingTabs[TabIdentity(tab), default: 0] += 1 }
        for tab in incoming.tabs where allowed(tab) {
            let key = TabIdentity(tab)
            if let count = existingTabs[key], count > 0 {
                existingTabs[key] = count - 1
            } else {
                data.tabs.append(tab)
                result.tabs += 1
            }
        }

        var closed = Set(data.closed.compactMap(\.closedAt))
        data.closed += incoming.closed.filter {
            allowed($0) && ($0.closedAt.map { closed.insert($0).inserted } ?? false)
        }
        data.closed = Array(data.closed.sorted { ($0.closedAt ?? .distantPast) < ($1.closedAt ?? .distantPast) }.suffix(25))
        return result
    }

    private static func mergeBookmarks(_ incoming: BrowserData, into data: inout BrowserData) -> Int {
        var folders = data.bookmarkFolders ?? []
        var known = Set((data.bookmarks + folders.flatMap(\.pages)).map(\.url))
        let before = known.count
        data.bookmarks += incoming.bookmarks.filter { Address.isWeb($0.url) && known.insert($0.url).inserted }
        let children = Dictionary(grouping: incoming.bookmarkFolders ?? [], by: \.parentID)
        var visited: Set<UUID> = []

        func append(_ folder: BookmarkFolder, parent: UUID?, depth: Int) {
            guard depth < 64, visited.insert(folder.id).inserted else { return }
            let name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let index: Int
            if let match = folders.firstIndex(where: {
                $0.parentID == parent && $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) {
                index = match
            } else {
                index = folders.count
                folders.append(BookmarkFolder(name: name, parentID: parent))
            }
            folders[index].pages += folder.pages.filter { Address.isWeb($0.url) && known.insert($0.url).inserted }
            let id = folders[index].id
            for child in children[folder.id] ?? [] { append(child, parent: id, depth: depth + 1) }
        }

        for folder in children[nil] ?? [] { append(folder, parent: nil, depth: 0) }
        data.bookmarkFolders = folders
        return known.count - before
    }
}
