import AppKit
import Foundation
import SwiftUI
import WebKit

struct DownloadItem: Identifiable, Codable {
    enum State: Codable {
        case downloading(Progress)
        case complete
        case failed(String)

        private enum Stored: Codable {
            case active
            case complete
            case failed(String)
        }

        init(from decoder: Decoder) throws {
            switch try Stored(from: decoder) {
            case .active: self = .failed("Загрузка прервана")
            case .complete: self = .complete
            case .failed(let message): self = .failed(message)
            }
        }

        func encode(to encoder: Encoder) throws {
            let stored: Stored
            switch self {
            case .downloading: stored = .active
            case .complete: stored = .complete
            case .failed(let message): stored = .failed(message)
            }
            try stored.encode(to: encoder)
        }
    }

    var id = UUID()
    let name: String
    let destination: URL?
    var sourceURL: URL?
    var startedAt = Date()
    var state: State

    var localFile: URL? {
        guard let destination, destination.isFileURL,
              FileManager.default.fileExists(atPath: destination.path) else { return nil }
        return destination
    }

    static func historySource(_ url: URL?) -> URL? {
        guard let url, var source = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = source.scheme?.lowercased(), ["https", "http"].contains(scheme),
              source.host?.isEmpty == false else { return nil }
        source.user = nil
        source.password = nil
        source.query = nil
        source.fragment = nil
        return source.url
    }

    var isComplete: Bool {
        if case .complete = state { return true }
        return false
    }
}

@MainActor
final class Downloads: NSObject, ObservableObject, WKDownloadDelegate {
    @Published private(set) var items: [DownloadItem]
    private let directory: URL?
    private let defaults: UserDefaults?
    private let preferences: UserDefaults?
    private var active: [ObjectIdentifier: (download: WKDownload, id: UUID)] = [:]
    private static var reservedPaths: Set<String> = []

    init(directory: URL? = nil, defaults: UserDefaults? = nil, preferences: UserDefaults? = nil) {
        self.directory = directory
        self.defaults = defaults
        self.preferences = preferences ?? defaults
        items = defaults?.data(forKey: "download-history")
            .flatMap { try? JSONDecoder().decode([DownloadItem].self, from: $0) } ?? []
    }

    private func save() {
        guard let defaults, let encoded = try? JSONEncoder().encode(items) else { return }
        defaults.set(encoded, forKey: "download-history")
    }

    func destinationDirectory() throws -> URL {
        if let directory { return directory }
        if let path = preferences?.string(forKey: BrowserPreference.downloadsFolder), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return try FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let id = ObjectIdentifier(download)
        let name = suggestedFilename.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last
            .map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let filename = name.isEmpty || name == "." || name == ".." ? "Загрузка" : name
        let sourceURL = DownloadItem.historySource(response.url)
        do {
            let folder = try destinationDirectory()
            if preferences?.bool(forKey: BrowserPreference.askDownloadFolder) == true {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.directoryURL = folder
                panel.prompt = "Сохранить сюда"
                panel.message = "Куда сохранить «\(filename)»?"
                panel.begin { [weak self, weak download] result in
                    guard result == .OK, let self, let download, let folder = panel.url else {
                        completionHandler(nil)
                        return
                    }
                    completionHandler(self.register(download, id: id, file: filename, source: sourceURL, folder: folder))
                }
            } else {
                completionHandler(register(download, id: id, file: filename, source: sourceURL, folder: folder))
            }
        } catch {
            items.insert(DownloadItem(name: filename, destination: nil,
                                      sourceURL: sourceURL,
                                      state: .failed(error.localizedDescription)), at: 0)
            save()
            completionHandler(nil)
        }
    }

    private func register(_ download: WKDownload, id: ObjectIdentifier, file: String,
                          source: URL?, folder: URL) -> URL {
        let destination = reserve(file, in: folder)
        let item = DownloadItem(name: destination.lastPathComponent, destination: destination,
                                sourceURL: source, state: .downloading(download.progress))
        active[id] = (download, item.id)
        items.insert(item, at: 0)
        save()
        return destination
    }

    private struct DownloadIdentity: Hashable {
        let name: String
        let date: Date
        init(_ item: DownloadItem) {
            name = item.name
            date = item.startedAt
        }
    }

    func importHistory(_ incoming: [DownloadItem]) -> Int {
        var known = Set(items.map(DownloadIdentity.init))
        let added = incoming.filter { known.insert(DownloadIdentity($0)).inserted }.map { item in
            DownloadItem(name: item.name, destination: nil, sourceURL: DownloadItem.historySource(item.sourceURL),
                         startedAt: item.startedAt, state: item.isComplete ? .complete : .failed("Загрузка не завершена"))
        }
        if !added.isEmpty {
            items += added
            items.sort { $0.startedAt > $1.startedAt }
            save()
        }
        return added.count
    }

    func removeFromHistory(_ id: UUID) {
        items.removeAll { item in
            guard item.id == id else { return false }
            if case .downloading = item.state { return false }
            return true
        }
        save()
    }

    private func reserve(_ filename: String, in folder: URL) -> URL {
        let original = folder.appendingPathComponent(filename, isDirectory: false)
        let stem = original.deletingPathExtension().lastPathComponent
        let suffix = original.pathExtension.isEmpty ? "" : "." + original.pathExtension
        var candidate = original
        var count = 1
        while Self.reservedPaths.contains(candidate.path.lowercased()) ||
                FileManager.default.fileExists(atPath: candidate.path) ||
                (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil {
            candidate = folder.appendingPathComponent("\(stem) (\(count))\(suffix)", isDirectory: false)
            count += 1
        }
        Self.reservedPaths.insert(candidate.path.lowercased())
        return candidate
    }

    func downloadDidFinish(_ download: WKDownload) {
        finish(download, as: .complete)
    }

    func cancel(_ id: UUID) {
        guard let task = active.values.first(where: { $0.id == id })?.download else { return }
        task.cancel { [weak self, weak task] _ in
            if let task { self?.finish(task, as: .failed("Загрузка отменена")) }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        finish(download, as: .failed(error.localizedDescription))
    }

    private func finish(_ download: WKDownload, as state: DownloadItem.State) {
        guard let download = active.removeValue(forKey: ObjectIdentifier(download)),
              let index = items.firstIndex(where: { $0.id == download.id }) else { return }
        if let path = items[index].destination?.path {
            Self.reservedPaths.remove(path.lowercased())
        }
        items[index].state = state
        save()
    }
}

