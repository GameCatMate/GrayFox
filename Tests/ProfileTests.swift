import AppKit
import Foundation
import SQLite3
import WebKit

@main
struct ProfileTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let origin = WebsiteOrigin(URL(string: "https://Example.org:443/login")!)!
        let anotherPort = WebsiteOrigin(URL(string: "https://example.org:8443/")!)!
        assert(origin.url.absoluteString == "https://example.org")
        assert(origin != anotherPort)
        assert(WebsiteOrigin(URL(string: "http://example.org")!) != origin)
        let login = SavedLogin(origin: origin, username: "test-account", password: "fixture-only,\"secret\"")
        let other = SavedLogin(origin: origin, username: "another-account", password: "another-fixture-secret")
        assert(SavedLogin.matching(in: [login, other], origin: origin, username: "") == nil)
        assert(SavedLogin.matching(in: [login, other], origin: origin, username: login.username) == login)
        assert(SavedLogin.matching(in: [login], origin: anotherPort, username: "") == nil)

        let csv = "name,url,username,password\r\n" +
            "Export,https://example.org/login,test-account,\"fixture-only,\"\"secret\"\"\"\r\n" +
            "Skipped,file:///tmp/example,case,fixture-password\r\n"
        let passwords = try PasswordImport.decode(Data(csv.utf8))
        assert(passwords.entries == [login] && passwords.skipped == 1)
        assert((try? PasswordImport.decode(Data("url,username,password\n\"bad".utf8))) == nil)
        let exportedYandex = "url;login;password\nhttp://example.org;test;legacy-fixture\nhttps://example.org;;userless-fixture\n"
        let importedYandex = try PasswordImport.decode(Data([0xFF, 0xFE]) + exportedYandex.data(using: .utf16LittleEndian)!)
        assert(importedYandex.entries.count == 2 && importedYandex.skipped == 0)

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appending(path: "Default/Sessions"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appending(path: "Default")
        let bookmarks = #"{"roots":{"bookmark_bar":{"type":"folder","name":"Bar","children":[{"type":"folder","name":"Nested","children":[{"type":"url","name":"Example","url":"https://example.org/"}]}]}}}"#
        try Data(bookmarks.utf8).write(to: folder.appending(path: "Bookmarks"))
        try testHistory(at: folder.appending(path: "History"))
        try session().write(to: folder.appending(path: "Sessions/Session_200"))

        let vivaldi = try ChromiumProfile.read(directory: directory, source: .vivaldi)
        let yandex = try ChromiumProfile.read(directory: folder, source: .yandex)
        assert(vivaldi.skipped.isEmpty && yandex.skipped.isEmpty, "Skipped: \(vivaldi.skipped), \(yandex.skipped)")
        assert(vivaldi.contents.browser.bookmarkFolders?.map(\.name) == ["Vivaldi", "Bar", "Nested"])
        assert(yandex.contents.browser.bookmarkFolders?.first?.name == "Яндекс Браузер")
        assert(vivaldi.contents.browser.history.first?.url.absoluteString == "https://example.org/")
        assert(vivaldi.contents.downloads.first?.name == "sample.pdf" && vivaldi.contents.downloads.first?.destination == nil)
        assert(vivaldi.contents.browser.tabs.count == 2)
        assert(vivaldi.contents.browser.tabs.first?.page?.title == "Current")
        assert(vivaldi.contents.browser.tabs.first?.pinned == true)
        assert(vivaldi.contents.browser.tabs.first?.group == "Work")
        assert(vivaldi.contents.browser.groupTints?["Work"] == .blue)
        assert(yandex.contents.browser.tabs.last?.group == "Яндекс Браузер")
        let workspaceSession = session() + command(21, pickle(little(10) +
            string(#"{"workspaceId":123456}"#)))
        let workspaces = try ChromiumSession.read(workspaceSession, defaultGroup: "Vivaldi",
                                                  workspaceNames: [123456: "Personal"])
        assert(workspaces.tabs.first?.group == "Personal")
        let localSession = session() + command(6, pickle(little(10) + little(1) +
            string("file:///tmp/mybro-import-fixture.pdf") + string("Local", utf16: true)))
        let localTabs = try ChromiumSession.read(localSession, defaultGroup: "Vivaldi")
        assert(localTabs.tabs.first?.localFile?.lastPathComponent == "mybro-import-fixture.pdf")

        try Data("SNSS\u{05}\u{00}\u{00}\u{00}".utf8).write(to: folder.appending(path: "Sessions/Session_201"))
        let fallback = try ChromiumProfile.read(directory: folder, source: .vivaldi)
        assert(fallback.contents.browser.tabs.count == 2 && fallback.skipped.count == 1)

        let tabsFile = directory.appending(path: "mybro-tabs.json")
        let passwordsFile = directory.appending(path: "passwords.csv")
        try Data("""
            {"version":1,"groups":[{"id":1,"window":5,"title":"Study","color":"green"}],
             "tabs":[{"window":5,"index":0,"group":1,"pinned":true,"title":"Active","url":"https://example.org/open"},
             {"window":5,"index":1,"group":null,"pinned":false,"title":"Insecure","url":"file:///tmp/ignore"},
             {"window":8,"index":0,"group":null,"pinned":false,"title":"Other window","url":"https://example.org/other"}],
             "skipped":1}
            """.utf8).write(to: tabsFile)
        try Data(csv.utf8).write(to: passwordsFile)
        let plan = try BrowserMigration.inspect(.init(source: .vivaldi, directory: folder,
                                                      tabsFile: tabsFile, passwordsFile: passwordsFile))
        assert(plan.counts.visits == 1 && plan.counts.passwords == 1 && plan.counts.tabs == 2)
        assert(plan.contents.browser.tabs.first?.page?.title == "Active")
        assert(plan.contents.browser.tabs.first?.pinned == true)
        assert(plan.contents.browser.groups == ["Vivaldi · Study", "Vivaldi · Окно 2"])
        assert(plan.contents.browser.groupTints?["Vivaldi · Study"] == .green)
        assert(plan.warnings.contains { $0.contains("вкладок: 2") })
        assert(plan.warnings.contains { $0.contains("паролей: 1") })
        assert(!plan.warnings.contains { $0.contains("более ранняя") })
        let launch = try BrowserMigration.Inputs.launchArguments([
            "myBro", "--mybro-import", "Vivaldi", folder.path, passwordsFile.path
        ])
        assert(launch?.directory?.path == folder.path && launch?.passwordsFile?.path == passwordsFile.path)
        let noLaunch = try BrowserMigration.Inputs.launchArguments(["myBro"])
        assert(noLaunch == nil)

        var payload = vivaldi.contents
        payload.passwords = [login]
        payload.preferences = ["address-search-engine": "DuckDuckGo"]
        let phrase = "only a synthetic test phrase"
        let archive = try ProfileArchive.encode(payload, passphrase: phrase)
        let decoded = try ProfileArchive.decode(archive, passphrase: phrase)
        assert(archive.range(of: Data(login.password.utf8)) == nil && decoded.passwords == [login])
        assert(decoded.preferences == payload.preferences)
        assert((try? ProfileArchive.decode(archive, passphrase: "wrong passphrase")) == nil)
        var altered = archive
        altered[altered.count - 1] ^= 1
        assert((try? ProfileArchive.decode(altered, passphrase: phrase)) == nil)

        var state = BrowserData()
        let first = ProfileImportResult.merge(decoded.browser, into: &state)
        let repeated = ProfileImportResult.merge(decoded.browser, into: &state)
        assert(first.bookmarks == 1 && first.tabs == 2 && first.visits == 1)
        assert(repeated.bookmarks == 0 && repeated.tabs == 0 && repeated.visits == 0)
        assert(state.bookmarkFolders?.last?.parentID == state.bookmarkFolders?[1].id)
        print("Keychain account matching, CSV, Chromium profile files, encrypted archive and repeat import checks passed.")

        if CommandLine.arguments.contains("--webkit") { try webKit() }
    }

    private static func testHistory(at file: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(file.path, &db) == SQLITE_OK else { throw ProfileError.invalidHistory }
        defer { sqlite3_close(db) }
        let output = sqlite3_exec(db, """
            CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT, title TEXT);
            CREATE TABLE visits(url INTEGER, visit_time INTEGER);
            INSERT INTO urls VALUES(1,'https://example.org/','Example');
            INSERT INTO visits VALUES(1,13322492123000000);
            CREATE TABLE downloads(id INTEGER, target_path TEXT, start_time INTEGER, state INTEGER);
            CREATE TABLE downloads_url_chains(id INTEGER,chain_index INTEGER,url TEXT);
            INSERT INTO downloads VALUES(7,'/origin/path/sample.pdf',13322492123000000,1);
            INSERT INTO downloads_url_chains VALUES(7,0,'https://example.org/sample.pdf?tracking=test');
            """, nil, nil, nil)
        guard output == SQLITE_OK else { throw ProfileError.invalidHistory }
    }

    private static func little(_ value: Int, length: Int = 4) -> Data {
        Data((0..<length).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    private static func string(_ value: String, utf16: Bool = false) -> Data {
        let bytes = utf16 ? value.data(using: .utf16LittleEndian)! : Data(value.utf8)
        let count = utf16 ? value.utf16.count : bytes.count
        return little(count) + bytes + Data(repeating: 0, count: (4 - bytes.count % 4) % 4)
    }

    private static func command(_ id: UInt8, _ payload: Data) -> Data {
        little(payload.count + 1, length: 2) + Data([id]) + payload
    }

    private static func pickle(_ payload: Data) -> Data {
        little(payload.count) + payload
    }

    private static func session() -> Data {
        var data = Data("SNSS".utf8) + little(3)
        let group = little(100, length: 8) + little(200, length: 8)
        data += command(27, pickle(group + string("Work", utf16: true) + little(1)))
        for id in [10, 11, 12] {
            data += command(0, little(4) + little(id))
            data += command(2, little(id) + little(id))
            let prior = little(id) + little(0) + string("https://old.example.org/") + string("Old", utf16: true)
            let current = little(id) + little(1) + string("https://current.example.org/\(id)") + string("Current", utf16: true)
            data += command(6, pickle(prior))
            data += command(6, pickle(current))
            data += command(7, little(id) + little(1))
        }
        data += command(12, little(10) + little(1))
        data += command(25, little(10) + little(0) + group + Data([1]) + Data(count: 7))
        data += command(16, little(11) + Data(count: 12))
        data += command(255, Data())
        return data
    }

    @MainActor private static func webKit() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let vault = PasswordVault(service: "org.mybro.tests.\(suite)")
        let origin = WebsiteOrigin(URL(string: "https://mybro-password-fixture.example/")!)!
        let login = SavedLogin(origin: origin, username: "fixture-user", password: "fixture-secret")
        defer {
            try? vault.remove(login)
            defaults.removePersistentDomain(forName: suite)
        }
        let file = FileManager.default.temporaryDirectory.appending(path: "myBro-\(suite).csv")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("url,username,password\n\(origin.url.absoluteString),\(login.username),\(login.password)\n".utf8)
            .write(to: file, options: .atomic)
        var migration = try BrowserMigration.inspect(.init(source: .vivaldi, passwordsFile: file))
        migration.contents.preferences[PasswordForms.autofillKey] = "true"
        let browser = Browser(defaults: defaults, passwordVault: vault)
        let result = try browser.importProfile(migration.contents)
        assert(result.passwords == 1 && browser.passwordAutofill)
        let stored = try vault.entries()
        assert(stored == [login])
        let web = browser.prepare(browser.active!)
        let html = """
            <form method="post" action="/session">
              <input id="user" autocomplete="username"><input id="pass" type="password" autocomplete="current-password">
              <button type="submit">Sign in</button>
            </form><script>
              document.querySelector("form").addEventListener("submit", event => event.preventDefault());
              document.addEventListener("change", () => { document.title = document.querySelector("#pass").value ? "filled" : "blank"; });
            </script>
            """
        let bounds = NSRect(x: 0, y: 0, width: 700, height: 420)
        let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
        web.frame = bounds
        window.contentView = web
        web.loadHTMLString(html, baseURL: origin.url)
        try wait("autofill") { web.title == "filled" }
        web.evaluateJavaScript("""
            document.querySelector("#pass").value = "fixture-updated";
            document.querySelector("form").requestSubmit();
            """)
        try wait("save prompt") { browser.pendingLogin?.password == "fixture-updated" }
        browser.savePendingLogin(browser.pendingLogin!)
        let updated = try vault.entries()
        assert(updated.first?.password == "fixture-updated")

        let signal = "<script>document.addEventListener('change', () => {if(document.querySelector('#pass')?.value) document.title='filled';});</script>"
        for (name, fields) in [
            ("formless", "<div><input id='user' name='login'><input id='pass' type='password'></div>"),
            ("password only", "<form><input id='pass' type='password'></form>"),
            ("read-only username", "<form><input id='user' value='fixture-user' readonly><input id='pass' type='password'></form>")
        ] {
            web.loadHTMLString(fields + signal, baseURL: origin.url)
            try wait(name) { web.title == "filled" }
        }
        for fields in [
            "<form><input id='user' name='username' autocomplete='email'><button>Далее</button></form>",
            "<div><input id='user' autocomplete='username'><button>Продолжить</button></div>"
        ] {
            web.loadHTMLString(fields + "<script>document.addEventListener('change', () => {if(document.querySelector('#user').value) document.title='username';});</script>", baseURL: origin.url)
            try wait("username first") { web.title == "username" }
            web.evaluateJavaScript("document.body.innerHTML = `<form><input id='pass' type='password'></form>`; document.addEventListener('change', () => {if(document.querySelector('#pass')?.value) document.title='filled';});")
            try wait("password second") { web.title == "filled" }
        }
        let formTab = browser.active!
        let otherTab = browser.newTab()
        web.loadHTMLString(html, baseURL: origin.url)
        try wait("background page") { !web.isLoading }
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        assert(web.title != "filled")
        browser.select(formTab)
        try wait("autofill on tab selection") { web.title == "filled" }
        browser.close(otherTab)

        let secondLogin = SavedLogin(origin: origin, username: "other-user", password: "other-fixture-password")
        try vault.save(secondLogin)
        defer { try? vault.remove(secondLogin) }
        web.loadHTMLString(html, baseURL: origin.url)
        try wait("ambiguous accounts load") { !web.isLoading }
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        assert(web.title != "filled")
        web.evaluateJavaScript("document.querySelector('#user').value='fixture-user'; document.querySelector('#user').dispatchEvent(new Event('input', {bubbles:true}));")
        try wait("chosen account") { web.title == "filled" }

        let externalForm = "<title>external form</title>" + html.replacingOccurrences(
            of: "/session", with: "https://other-site.example/session"
        )
        web.loadHTMLString(externalForm, baseURL: origin.url)
        try wait("external form") { web.title == "external form" && !web.isLoading }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        assert(web.title == "external form")

        let privateBrowser = Browser(isPrivate: true, passwordVault: vault)
        let privateWeb = privateBrowser.prepare(privateBrowser.active!)
        window.contentView = privateWeb
        privateWeb.loadHTMLString(html, baseURL: origin.url)
        try wait("private load") { privateWeb.url != nil && !privateWeb.isLoading }
        let until = Date().addingTimeInterval(0.5)
        RunLoop.main.run(until: until)
        assert(privateWeb.title != "filled" && privateBrowser.pendingLogin == nil)
        print("Local WebKit verified form and formless login, username-first steps, password-only forms, account matching, tab reactivation, explicit save and private isolation.")
    }

    @MainActor private static func wait(_ label: String, until condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(8)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        if !condition() { throw NSError(domain: "Timed out: " + label, code: 1) }
    }
}
