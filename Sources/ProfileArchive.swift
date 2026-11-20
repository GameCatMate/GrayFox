import CommonCrypto
import CryptoKit
import Foundation
import Security

enum ProfileError: LocalizedError {
    case invalidFile
    case tooLarge
    case invalidPassphrase
    case authentication
    case keychain(OSStatus)
    case unsupportedSession
    case invalidHistory

    var errorDescription: String? {
        switch self {
        case .invalidFile: "Формат файла не поддерживается или файл повреждён."
        case .tooLarge: "Файл превышает допустимый размер."
        case .invalidPassphrase: "Введите одинаковую парольную фразу длиной от 12 символов."
        case .authentication: "Парольная фраза неверна или архив повреждён."
        case let .keychain(status): "Связка ключей недоступна (\(status))."
        case .unsupportedSession: "Формат файла вкладок не поддерживается."
        case .invalidHistory: "Не удалось прочитать историю из выбранного профиля."
        }
    }
}

struct ProfileContents: Codable {
    var browser = BrowserData()
    var passwords: [SavedLogin] = []
    var downloads: [DownloadItem] = []
    var preferences: [String: String] = [:]
}

enum ProfileArchive {
    private static let header = Data("MYBROPF1".utf8)
    private static let saltSize = 16
    static let fileLimit = 128 * 1024 * 1024

    static func encode(_ profile: ProfileContents, passphrase: String) throws -> Data {
        guard passphrase.count >= 12 else { throw ProfileError.invalidPassphrase }
        var salt = Data(count: saltSize)
        let status = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, saltSize, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw ProfileError.keychain(status) }
        let prefix = header + salt
        let payload = try JSONEncoder().encode(profile)
        guard payload.count <= fileLimit - prefix.count - 28 else { throw ProfileError.tooLarge }
        let key = try derive(passphrase, salt: salt)
        guard let sealed = try AES.GCM.seal(payload, using: key, authenticating: prefix).combined else {
            throw ProfileError.authentication
        }
        return prefix + sealed
    }

    static func decode(_ archive: Data, passphrase: String) throws -> ProfileContents {
        let prefixSize = header.count + saltSize
        guard archive.count <= fileLimit, archive.count >= prefixSize + 28,
              archive.starts(with: header) else { throw ProfileError.invalidFile }
        let prefix = Data(archive.prefix(prefixSize))
        let key = try derive(passphrase, salt: Data(prefix.suffix(saltSize)))
        let sealed = try AES.GCM.SealedBox(combined: archive.dropFirst(prefixSize))
        guard let payload = try? AES.GCM.open(sealed, using: key, authenticating: prefix) else {
            throw ProfileError.authentication
        }
        return try JSONDecoder().decode(ProfileContents.self, from: payload)
    }

    static func read(_ file: URL, limit: Int) throws -> Data {
        let source = try FileHandle(forReadingFrom: file)
        defer { try? source.close() }
        let data = try source.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ProfileError.tooLarge }
        return data
    }

    private static func derive(_ passphrase: String, salt: Data) throws -> SymmetricKey {
        let password = Array(passphrase.utf8)
        guard !password.isEmpty, password.count <= 1024 else { throw ProfileError.authentication }
        var key = Data(count: 32)
        let result = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress!.assumingMemoryBound(to: Int8.self), password.count,
                        saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000,
                        keyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), 32
                    )
                }
            }
        }
        guard result == kCCSuccess else { throw ProfileError.authentication }
        return SymmetricKey(data: key)
    }
}

struct PasswordImport {
    var entries: [SavedLogin] = []
    var skipped = 0

    static func decode(_ data: Data) throws -> PasswordImport {
        let decoded: String?
        if data.starts(with: [0xFF, 0xFE]) {
            decoded = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        } else if data.starts(with: [0xFE, 0xFF]) {
            decoded = String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        } else {
            decoded = String(data: data, encoding: .utf8)
        }
        guard var text = decoded else { throw ProfileError.invalidFile }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let header = text.prefix { !$0.isNewline }
        let rows = try csv(text, separator: header.contains(",") ? "," : ";")
        guard let columns = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }),
              let site = columns.firstIndex(where: { ["url", "origin", "website", "site", "сайт"].contains($0) }),
              let user = columns.firstIndex(where: { ["username", "login", "user", "логин"].contains($0) }),
              let secret = columns.firstIndex(where: { ["password", "пароль"].contains($0) })
        else { throw ProfileError.invalidFile }

        var result = PasswordImport()
        for row in rows.dropFirst() where row.contains(where: { !$0.isEmpty }) {
            guard row.count > max(site, user, secret), let url = URL(string: row[site]),
                  let origin = WebsiteOrigin(url) else {
                result.skipped += 1
                continue
            }
            let entry = SavedLogin(origin: origin, username: row[user], password: row[secret])
            if entry.isValid { result.entries.append(entry) } else { result.skipped += 1 }
        }
        return result
    }

    private static func csv(_ text: String, separator: Character) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var closedQuote = false
        var i = text.startIndex
        while i < text.endIndex {
            let character = text[i]
            i = text.index(after: i)
            if quoted {
                if character == "\"" {
                    if i < text.endIndex, text[i] == "\"" {
                        field.append("\"")
                        i = text.index(after: i)
                    } else {
                        quoted = false
                        closedQuote = true
                    }
                } else {
                    field.append(character)
                }
            } else if character == separator || character.isNewline {
                row.append(field)
                field = ""
                closedQuote = false
                if character.isNewline {
                    rows.append(row)
                    row.removeAll()
                }
            } else if character == "\"", field.isEmpty, !closedQuote {
                quoted = true
            } else {
                guard !closedQuote, character != "\"" else { throw ProfileError.invalidFile }
                field.append(character)
            }
        }
        guard !quoted else { throw ProfileError.invalidFile }
        if !row.isEmpty || !field.isEmpty || closedQuote { rows.append(row + [field]) }
        return rows
    }
}
