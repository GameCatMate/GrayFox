import Foundation
import Security

struct WebsiteOrigin: Hashable, Codable {
    let url: URL

    init?(_ url: URL) {
        guard Address.isWeb(url), let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              let canonical = Self.url(scheme: scheme, host: host, port: url.port) else { return nil }
        self.url = canonical
    }

    private static func url(scheme: String, host: String, port: Int?) -> URL? {
        let defaultPort = scheme == "https" ? 443 : 80
        let port = port ?? defaultPort
        guard (1...65535).contains(port) else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port == defaultPort ? nil : port
        return components.url
    }
}

struct SavedLogin: Identifiable, Codable, Equatable {
    struct ID: Hashable {
        let origin: WebsiteOrigin
        let username: String
    }

    let origin: WebsiteOrigin
    let username: String
    let password: String

    var id: ID { ID(origin: origin, username: username) }
    var isValid: Bool {
        WebsiteOrigin(origin.url) == origin && !password.isEmpty &&
            username.utf8.count <= 1024 && password.utf8.count <= 4096
    }

    static func matching(in entries: [SavedLogin], origin: WebsiteOrigin, username: String) -> SavedLogin? {
        let matching = entries.filter { $0.origin == origin }
        if !username.isEmpty { return matching.first { $0.username == username } }
        return matching.count == 1 ? matching.first : nil
    }
}

struct PasswordVault {
    let service: String

    init(service: String = "org.openstvor.browser.passwords") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "local-profile"]
    }

    func entries() throws -> [SavedLogin] {
        var result: CFTypeRef?
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status)
        guard let data = result as? Data else { throw ProfileError.invalidFile }
        return try JSONDecoder().decode([SavedLogin].self, from: data).filter(\.isValid)
    }

    func save(_ entry: SavedLogin) throws {
        try merge([entry], replaceExisting: true)
    }

    @discardableResult
    func merge(_ incoming: [SavedLogin], replaceExisting: Bool = false) throws -> Int {
        guard incoming.allSatisfy(\.isValid) else { throw ProfileError.invalidFile }
        guard !incoming.isEmpty else { return 0 }
        var current = try entries()
        var positions: [SavedLogin.ID: Int] = [:]
        for (index, entry) in current.enumerated() { positions[entry.id] = index }
        var added = 0
        for entry in incoming {
            if let index = positions[entry.id] {
                if replaceExisting { current[index] = entry }
            } else {
                positions[entry.id] = current.count
                current.append(entry)
                added += 1
            }
        }
        if replaceExisting || added > 0 { try write(current) }
        return added
    }

    func remove(_ entry: SavedLogin) throws {
        let remaining = try entries().filter { $0.id != entry.id }
        if remaining.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
        } else {
            try write(remaining)
        }
    }

    private func write(_ entries: [SavedLogin]) throws {
        let data = try JSONEncoder().encode(entries)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "myBro"
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw ProfileError.keychain(status)
        }
    }
}
