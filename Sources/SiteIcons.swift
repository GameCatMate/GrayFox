import AppKit
import ImageIO
import SwiftUI

@MainActor
final class SiteIcons: ObservableObject {
    @Published private var knownIcons: [WebsiteOrigin: URL] = [:]
    private let images = NSCache<NSURL, NSImage>()
    private var pending: [URL: Task<Data?, Never>] = [:]
    private var failures: [URL: Date] = [:]
    private let session: URLSession
    private nonisolated static let maximumBytes = 512 * 1024

    init(isPrivate: Bool = false) {
        let configuration = isPrivate ? URLSessionConfiguration.ephemeral : .default
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        if isPrivate { configuration.urlCache = nil }
        session = URLSession(configuration: configuration)
        images.countLimit = 256
        images.totalCostLimit = 1024 * 1024
    }

    deinit { session.invalidateAndCancel() }

    static func sources(for page: Page) -> [URL] {
        guard Address.isWeb(page.url), var root = URLComponents(url: page.url, resolvingAgainstBaseURL: false) else { return [] }
        root.path = "/favicon.ico"
        root.query = nil
        root.fragment = nil
        let candidates = [page.iconURL, root.url].compactMap { $0 }.filter(Address.isWeb)
        var seen: Set<URL> = []
        return candidates.filter { seen.insert($0).inserted }
    }

    func remember(_ iconURL: URL, for pageURL: URL) {
        guard Address.isWeb(iconURL), let origin = WebsiteOrigin(pageURL),
              knownIcons[origin] != iconURL else { return }
        knownIcons[origin] = iconURL
    }

    func candidates(for page: Page) -> [URL] {
        guard let origin = WebsiteOrigin(page.url) else { return [] }
        var shared = page
        shared.iconURL = knownIcons[origin]
        let explicit = [page.iconURL].compactMap { $0 }.filter(Address.isWeb)
        var seen: Set<URL> = []
        return (explicit + Self.sources(for: shared)).filter { seen.insert($0).inserted }
    }

    func cached(_ sources: [URL]) -> NSImage? {
        sources.lazy.compactMap { self.images.object(forKey: $0 as NSURL) }.first
    }

    func load(_ sources: [URL]) async -> NSImage? {
        for url in sources {
            if let image = images.object(forKey: url as NSURL) { return image }
            if let failed = failures[url], Date().timeIntervalSince(failed) < 10 { continue }
            let task = pending[url] ?? Task { await Self.download(url, session: session) }
            pending[url] = task
            let data = await task.value
            pending[url] = nil
            if let image = images.object(forKey: url as NSURL) { return image }
            guard let data, let image = Self.decode(data) else {
                failures[url] = .now
                continue
            }
            objectWillChange.send()
            images.setObject(image, forKey: url as NSURL, cost: 32 * 32 * 4)
            failures[url] = nil
            return image
        }
        return nil
    }

    private nonisolated static func download(_ url: URL, session: URLSession) async -> Data? {
        guard Address.isWeb(url) else { return nil }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                  response.expectedContentLength <= maximumBytes else { return nil }
            var data = Data()
            for try await byte in bytes {
                guard data.count < maximumBytes else { return nil }
                data.append(byte)
            }
            return data
        } catch { return nil }
    }

    static func decode(_ data: Data) -> NSImage? {
        guard data.count <= maximumBytes, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 32,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: 16, height: 16))
    }
}

struct SiteIcon: View {
    let page: Page
    @ObservedObject var icons: SiteIcons
    @State private var image: NSImage?

    var body: some View {
        let sources = icons.candidates(for: page)
        return Group {
            if let image = icons.cached(sources) ?? image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "globe").foregroundStyle(.secondary)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
        .task(id: sources) {
            image = icons.cached(sources)
            let loaded = await icons.load(sources)
            guard !Task.isCancelled else { return }
            image = loaded
            guard loaded == nil else { return }
            do { try await Task.sleep(for: .seconds(10)) }
            catch { return }
            let retried = await icons.load(sources)
            guard !Task.isCancelled else { return }
            image = retried
        }
    }
}
