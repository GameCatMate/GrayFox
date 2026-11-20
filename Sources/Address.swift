import Foundation

struct Page: Codable, Hashable, Identifiable {
    var title: String
    var url: URL
    var iconURL: URL? = nil
    var id: URL { url }
}

enum SearchEngine: String, CaseIterable {
    case google = "Google"
    case duckDuckGo = "DuckDuckGo"
    case bing = "Bing"
    case brave = "Brave Search"

    private var endpoint: (host: String, path: String) {
        switch self {
        case .google: ("www.google.com", "/search")
        case .duckDuckGo: ("duckduckgo.com", "/")
        case .bing: ("www.bing.com", "/search")
        case .brave: ("search.brave.com", "/search")
        }
    }

    func searchURL(_ text: String) -> URL? {
        var url = URLComponents()
        url.scheme = "https"
        url.host = endpoint.host
        url.path = endpoint.path
        url.queryItems = [URLQueryItem(name: "q", value: text)]
        return url.url
    }
}

struct SearchSuggestionRequest: Hashable {
    let engine: SearchEngine
    let query: String

    var url: URL {
        let endpoint: String
        let parameter: String
        switch engine {
        case .google:
            endpoint = "https://www.google.com/complete/search?client=firefox"
            parameter = "q"
        case .duckDuckGo:
            endpoint = "https://duckduckgo.com/ac/?type=list"
            parameter = "q"
        case .bing:
            endpoint = "https://www.bing.com/osjson.aspx"
            parameter = "query"
        case .brave:
            endpoint = "https://search.brave.com/api/suggest"
            parameter = "q"
        }
        var components = URLComponents(string: endpoint)!
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: parameter, value: query)]
        return components.url!
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 4
        return URLSession(configuration: configuration)
    }()

    func fetch() async throws -> [String] {
        let (data, response) = try await Self.session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return parse(data)
    }

    func parse(_ data: Data) -> [String] {
        guard data.count <= 128 * 1024, let response = try? JSONSerialization.jsonObject(with: data) as? [Any],
              response.count >= 2, let entries = response[1] as? [String] else { return [] }
        var seen: Set<String> = [query.lowercased()]
        return entries.prefix(16).compactMap { entry in
            let text = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 160, seen.insert(text.lowercased()).inserted else { return nil }
            return text
        }
    }
}

enum Address {
    static let suggestedSites = [
        ("YouTube", "https://youtube.com/"),
        ("Википедия · Wikipedia", "https://ru.wikipedia.org/"),
        ("GitHub", "https://github.com/"),
        ("Google", "https://www.google.com/"),
        ("DuckDuckGo", "https://duckduckgo.com/"),
        ("Telegram", "https://telegram.org/"),
        ("ВКонтакте · VK", "https://vk.com/"),
        ("Reddit", "https://www.reddit.com/")
    ].map { Page(title: $0.0, url: URL(string: $0.1)!) }

    private static let russianToLatin = Dictionary(uniqueKeysWithValues: zip(
        "йцукенгшщзхъфывапролджэячсмитьбю", "qwertyuiop[]asdfghjkl;'zxcvbnm,."
    ))

    private static func matchingQueries(_ input: String) -> [String] {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.count >= 2 else { return [] }
        let converted = String(query.map { russianToLatin[$0] ?? $0 })
        return converted == query ? [query] : [query, converted]
    }

    static func suggestions(for input: String, pages: [Page]) -> [Page] {
        let queries = matchingQueries(input)
        guard !queries.isEmpty else { return [] }
        var hostMatches: [Page] = []
        var otherMatches: [Page] = []
        var seen: Set<URL> = []
        for page in pages where isWeb(page.url) && seen.insert(page.url).inserted {
            if queries.contains(where: { hostMatchesQuery($0, page: page) }) {
                hostMatches.append(page)
            } else if queries.contains(where: {
                page.title.localizedCaseInsensitiveContains($0) || page.url.absoluteString.lowercased().contains($0)
            }) {
                otherMatches.append(page)
            }
        }
        return Array((hostMatches + otherMatches).prefix(6))
    }

    static func completesHost(_ input: String, with page: Page) -> Bool {
        matchingQueries(input).contains {
            $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } && hostMatchesQuery($0, page: page)
        }
    }

    private static func hostMatchesQuery(_ query: String, page: Page) -> Bool {
        guard let host = page.url.host?.lowercased() else { return false }
        return host.hasPrefix(query) || (host.hasPrefix("www.") && host.dropFirst(4).hasPrefix(query))
    }

    static func isWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") &&
            url.host?.isEmpty == false && url.user == nil && url.password == nil
    }

    static func navigationURL(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("\\"), !value.contains(where: \.isWhitespace) else { return nil }
        if let url = URL(string: value), isWeb(url) { return url }
        let host = value.split(whereSeparator: { "/?#:".contains($0) }).first ?? ""
        if host.contains(".") || host == "localhost" || value.hasPrefix("[") {
            if let url = URL(string: "https://" + value), isWeb(url) { return url }
        }
        return nil
    }

    static func searchQuery(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("\\"), navigationURL(value) == nil,
              value.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) == nil else { return nil }
        return value
    }

    static func networkQuery(_ text: String) -> String? {
        guard let query = searchQuery(text), (2...160).contains(query.count),
              !query.contains(where: { "@/".contains($0) }) else { return nil }
        return query
    }

    static func resolve(_ input: String, search: Bool = true, engine: SearchEngine = .google) -> URL? {
        navigationURL(input) ?? (search ? searchQuery(input).flatMap(engine.searchURL) : nil)
    }
}
