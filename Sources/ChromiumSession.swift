import Foundation

enum ChromiumSession {
    private struct TabState {
        var window: Int?
        var index = Int.max
        var selected: Int?
        var pinned = false
        var group: Data?
        var workspace: Int64?
        var pages: [Int: SavedTab] = [:]
    }

    static func read(_ data: Data, defaultGroup: String, workspaceNames: [Int64: String]? = nil) throws
        -> (tabs: [SavedTab], groups: [String], tints: [String: GroupTint]) {
        guard data.starts(with: Data("SNSS".utf8)), let version = int(data, 4),
              [1, 3].contains(version) else { throw ProfileError.unsupportedSession }
        var offset = 8
        var tabs: [Int: TabState] = [:]
        var closedWindows: Set<Int> = []
        var metadata: [Data: (String, GroupTint)] = [:]
        let colors: [GroupTint] = [.gray, .blue, .red, .orange, .green, .purple, .purple, .green, .orange]

        while offset < data.count {
            guard offset + 3 <= data.count else { throw ProfileError.unsupportedSession }
            let length = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            guard length > 0, offset + 2 + length <= data.count else { throw ProfileError.unsupportedSession }
            let operation = data[offset + 2]
            let payload = data.subdata(in: (offset + 3)..<(offset + 2 + length))
            offset += 2 + length

            // The command IDs and layouts are from Chromium session_service_commands.cc.
            switch operation {
            case 0:
                if let window = int(payload, 0), let tab = int(payload, 4) {
                    tabs[tab, default: TabState()].window = window
                }
            case 2:
                if let tab = int(payload, 0), let index = int(payload, 4) {
                    tabs[tab, default: TabState()].index = index
                }
            case 6:
                if let tab = int(payload, 4), let index = int(payload, 8), let raw = string(payload, at: 12),
                   let url = URL(string: raw.value) {
                    let title = string(payload, at: raw.next, unicode: true)?.value
                    if let page = restoredTab(url: url, title: title) {
                        tabs[tab, default: TabState()].pages[index] = page
                    } else {
                        tabs[tab, default: TabState()].pages.removeValue(forKey: index)
                    }
                }
            case 7:
                if let tab = int(payload, 0), let index = int(payload, 4) {
                    tabs[tab, default: TabState()].selected = index
                }
            case 12:
                if let tab = int(payload, 0), payload.count >= 5 {
                    tabs[tab, default: TabState()].pinned = payload[4] != 0
                }
            case 16:
                if let tab = int(payload, 0) { tabs.removeValue(forKey: tab) }
            case 17:
                if let window = int(payload, 0) { closedWindows.insert(window) }
            case 21 where workspaceNames != nil:
                if let tab = int(payload, 4), let json = string(payload, at: 8)?.value,
                   let bytes = json.data(using: .utf8),
                   let extra = try? JSONDecoder().decode(VivaldiTabData.self, from: bytes) {
                    tabs[tab, default: TabState()].workspace = extra.workspaceId
                }
            case 24:
                if let tab = int(payload, 0), let index = int(payload, 4), let count = int(payload, 8),
                   index >= 0, count > 0, let pages = tabs[tab]?.pages {
                    tabs[tab]?.pages = Dictionary(uniqueKeysWithValues: pages.compactMap { key, page in
                        if key < index { return (key, page) }
                        if key >= index + count { return (key - count, page) }
                        return nil
                    })
                }
            case 25:
                if let tab = int(payload, 0), payload.count == 32 {
                    tabs[tab, default: TabState()].group = payload[24] == 0 ? nil : payload.subdata(in: 8..<24)
                }
            case 27:
                if let title = string(payload, at: 20, unicode: true), let color = int(payload, title.next) {
                    let tint = colors.indices.contains(color) ? colors[color] : .blue
                    metadata[payload.subdata(in: 4..<20)] = (title.value, tint)
                }
            default: break
            }
        }

        var collected: [SavedTab] = []
        var names: [String] = []
        var tints: [String: GroupTint] = [:]
        var groupNames: [Data: String] = [:]

        for (_, tab) in tabs.sorted(by: { a, b in
            (a.value.window ?? Int.max, a.value.index, a.key) < (b.value.window ?? Int.max, b.value.index, b.key)
        }) {
            guard let window = tab.window, !closedWindows.contains(window) else { continue }
            let index = tab.selected ?? tab.pages.keys.max()
            guard let index, var restored = tab.pages[index] else { continue }

            var name = defaultGroup
            if let workspace = tab.workspace, let workspaceNames {
                name = workspaceNames[workspace] ?? "Рабочее пространство \(workspace)"
            } else if let group = tab.group {
                if let known = groupNames[group] {
                    name = known
                } else {
                    let title = metadata[group]?.0.trimmingCharacters(in: .whitespacesAndNewlines)
                    let base = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Группа"
                    name = base
                    var suffix = 2
                    while name == defaultGroup || names.contains(name) {
                        name = "\(base) (\(suffix))"
                        suffix += 1
                    }
                    groupNames[group] = name
                    tints[name] = metadata[group]?.1 ?? .blue
                }
            }

            if !names.contains(name) { names.append(name) }
            restored.group = name
            restored.pinned = tab.pinned
            collected.append(restored)
        }
        return (collected, names, tints)
    }

    private static func restoredTab(url: URL, title: String?) -> SavedTab? {
        if Address.isWeb(url) {
            let title = title.flatMap { $0.isEmpty ? nil : $0 } ?? url.host ?? url.absoluteString
            return SavedTab(page: Page(title: title, url: url))
        }
        if url.isFileURL, url.user == nil, url.password == nil, !url.path.isEmpty,
           url.host == nil || url.host == "" || url.host == "localhost" {
            return SavedTab(localFile: url)
        }
        guard ["chrome", "vivaldi", "browser", "yandex"].contains(url.scheme ?? "") else { return nil }
        switch url.host {
        case "newtab", "startpage", "vivaldi-webui": return SavedTab()
        case "history": return SavedTab(internalPage: .history)
        case "downloads": return SavedTab(internalPage: .downloads)
        case "bookmarks": return SavedTab(internalPage: .bookmarks)
        case "settings": return SavedTab(internalPage: .settings)
        case "password-manager": return SavedTab(internalPage: .passwords)
        case "extensions": return SavedTab(internalPage: .extensions)
        default: return nil
        }
    }

    private struct VivaldiTabData: Decodable {
        let workspaceId: Int64?
    }

    private static func int(_ data: Data, _ offset: Int) -> Int? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let bits = (0..<4).reduce(UInt32(0)) { result, index in
            result | (UInt32(data[offset + index]) << (index * 8))
        }
        return Int(Int32(bitPattern: bits))
    }

    private static func string(_ data: Data, at offset: Int, unicode: Bool = false)
        -> (value: String, next: Int)? {
        guard let count = int(data, offset), count >= 0 else { return nil }
        let size = unicode ? count * 2 : count
        let start = offset + 4
        guard start + size <= data.count,
              let value = String(data: data.subdata(in: start..<(start + size)),
                                 encoding: unicode ? .utf16LittleEndian : .utf8) else { return nil }
        return (value, start + ((size + 3) & ~3))
    }
}
