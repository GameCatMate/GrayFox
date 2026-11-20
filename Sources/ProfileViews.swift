import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PasswordManager: View {
    let browser: Browser
    @AppStorage(PasswordForms.autofillKey) private var autofill = true
    @State private var entries: [SavedLogin] = []
    @State private var status: String?
    @State private var editing = false
    @State private var updating = false
    @State private var website = ""
    @State private var username = ""
    @State private var password = ""
    @State private var removing: SavedLogin?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Пароли").font(.title2.weight(.semibold))
                Spacer()
                Button("Импорт CSV…") { importCSV() }
                Button("Добавить…") { edit(nil) }
            }
            Toggle("Автоматически подставлять сохранённые пароли", isOn: $autofill)
            if let status { Text(status).foregroundStyle(.secondary) }
            if entries.isEmpty {
                Text("Сохранённых паролей пока нет.").foregroundStyle(.secondary)
                Spacer()
            } else {
                List(entries) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.origin.url.absoluteString)
                            Text(entry.username).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Изменить…") { edit(entry) }
                        Button("Удалить", role: .destructive) { removing = entry }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 860, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { load() }
        .sheet(isPresented: $editing, onDismiss: { password = "" }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Сохранить логин").font(.headline)
                TextField("Сайт, например https://example.com", text: $website)
                    .disabled(updating)
                TextField("Имя пользователя", text: $username)
                    .disabled(updating)
                SecureField("Пароль", text: $password)
                HStack {
                    Spacer()
                    Button("Отмена") { editing = false }.keyboardShortcut(.cancelAction)
                    Button("Сохранить") {
                        guard let url = URL(string: website), let origin = WebsiteOrigin(url) else { return }
                        let entry = SavedLogin(origin: origin, username: username, password: password)
                        guard entry.isValid else { status = "Проверьте длину логина и пароля."; return }
                        do {
                            try browser.passwordVault.save(entry)
                            editing = false
                            status = nil
                            load()
                        } catch { status = error.localizedDescription; editing = false }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(URL(string: website).flatMap(WebsiteOrigin.init) == nil || username.isEmpty || password.isEmpty)
                }
            }
            .padding(16)
            .frame(width: 420)
        }
        .alert("Удалить сохранённый пароль?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        ), presenting: removing) { entry in
            Button("Удалить", role: .destructive) {
                do {
                    try browser.passwordVault.remove(entry)
                    status = nil
                    load()
                } catch { status = error.localizedDescription }
            }
            Button("Отмена", role: .cancel) {}
        } message: { entry in Text(entry.origin.url.absoluteString + " · " + entry.username) }
    }

    private func edit(_ entry: SavedLogin?) {
        updating = entry != nil
        website = entry?.origin.url.absoluteString ?? ""
        username = entry?.username ?? ""
        password = ""
        editing = true
    }

    private func load() {
        do {
            entries = try browser.passwordVault.entries().sorted {
                ($0.origin.url.absoluteString, $0.username) < ($1.origin.url.absoluteString, $1.username)
            }
        } catch { status = error.localizedDescription }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canChooseDirectories = false
        panel.message = "Выберите CSV, который экспортировали из менеджера паролей."
        panel.begin { response in
            guard response == .OK, let file = panel.url else { return }
            Task { @MainActor in
                do {
                    let imported = try await Task.detached {
                        try PasswordImport.decode(ProfileArchive.read(file, limit: 16 * 1024 * 1024))
                    }.value
                    let added = try browser.passwordVault.merge(imported.entries)
                    status = "Добавлено: \(added). Уже сохранено: \(imported.entries.count - added). Пропущено: \(imported.skipped)."
                    load()
                } catch { status = error.localizedDescription }
            }
        }
    }
}

struct ProfileTransferView: View {
    @ObservedObject var browser: Browser
    @State private var source: ChromiumProfile.Source = .vivaldi
    @State private var profileFolder: URL?
    @State private var tabsFile: URL?
    @State private var passwordsFile: URL?
    @State private var preview: BrowserMigration?
    @State private var useAutofill = true
    @State private var operation: ArchiveOperation?
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var status: String?
    @State private var working = false

    private enum ArchiveOperation: Identifiable {
        case export
        case restore(URL)

        var id: String { exporting ? "export" : "restore" }
        var exporting: Bool { if case .export = self { return true }; return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Перенос профиля").font(.title2.weight(.semibold))
            Form {
                Section("Импорт из другого браузера") {
                    Picker("Браузер", selection: $source) {
                        ForEach(ChromiumProfile.Source.allCases) { Text($0.rawValue).tag($0) }
                    }
                    importInput("Папка профиля", selection: $profileFolder) { chooseProfileFolder() }
                    importInput("Открытые вкладки или файл сессии", selection: $tabsFile) {
                        chooseFile("Выберите JSON из расширения myBro или поддерживаемый файл сохранённой сессии.",
                                   contentTypes: [.data], selection: $tabsFile)
                    }
                    importInput("Пароли из CSV", selection: $passwordsFile) {
                        chooseFile("Выберите CSV, экспортированный штатным менеджером паролей.",
                                   contentTypes: [.commaSeparatedText], selection: $passwordsFile)
                    }
                    if passwordsFile != nil {
                        Toggle("Включить автозаполнение после импорта паролей", isOn: $useAutofill)
                    }
                    DisclosureGroup("Как выгрузить открытые вкладки") {
                        Text("В исходном браузере откройте страницу расширений, включите режим разработчика и загрузите распакованное расширение myBro. Нажмите его значок и сохраните JSON. Затем выберите этот файл в мастере.")
                            .foregroundStyle(.secondary)
                        Button("Показать папку расширения") { showTabExporter() }
                    }
                    HStack {
                        Button("Проверить данные") { inspectImport() }
                            .disabled(profileFolder == nil && tabsFile == nil && passwordsFile == nil)
                        Button("Импортировать") { commitImport() }
                            .disabled(preview == nil)
                    }
                    if let preview {
                        let counts = preview.counts
                        Text("Найдено: вкладки — \(counts.tabs), группы — \(preview.contents.browser.groups.count), посещения — \(counts.visits), закладки — \(counts.bookmarks), загрузки — \(counts.downloads), пароли — \(counts.passwords).")
                        ForEach(preview.warnings, id: \.self) { Text($0).foregroundStyle(.secondary) }
                    }
                }
                Section("Архив myBro") {
                    Button("Экспортировать зашифрованный архив…") { operation = .export }
                    Button("Импортировать архив myBro…") { chooseArchive() }
                }
            }
            .formStyle(.grouped)
            .disabled(working)
            if working { ProgressView().controlSize(.small) }
            if let status { Text(status).textSelection(.enabled) }
            else if let status = browser.migrationStatus { Text(status).textSelection(.enabled) }
        }
        .padding(16)
        .frame(maxWidth: 700, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { useAutofill = browser.passwordAutofill }
        .onChange(of: source) {
            profileFolder = nil
            tabsFile = nil
            passwordsFile = nil
            preview = nil
            status = nil
        }
        .sheet(item: $operation, onDismiss: clearPassphrase) { action in
            VStack(alignment: .leading, spacing: 12) {
                Text(action.exporting ? "Защитить архив" : "Открыть архив").font(.headline)
                SecureField("Парольная фраза", text: $passphrase)
                if action.exporting {
                    SecureField("Повторите парольную фразу", text: $confirmation)
                    Text("Минимум 12 символов. Эта фраза потребуется для импорта.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Отмена") { operation = nil }.keyboardShortcut(.cancelAction)
                    Button(action.exporting ? "Продолжить" : "Импортировать") {
                        let secret = passphrase
                        operation = nil
                        switch action {
                        case .export: exportArchive(passphrase: secret)
                        case let .restore(file): restoreArchive(file, passphrase: secret)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(passphrase.isEmpty || (action.exporting && (passphrase.count < 12 || passphrase != confirmation)))
                }
            }
            .padding(16)
            .frame(width: 420)
        }
    }

    private func clearPassphrase() {
        passphrase = ""
        confirmation = ""
    }

    private func importInput(_ title: String, selection: Binding<URL?>,
                             choose: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let file = selection.wrappedValue {
                    Text(file.lastPathComponent).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button("Выбрать…", action: choose)
                .accessibilityLabel("Выбрать: \(title)")
            if selection.wrappedValue != nil {
                Button("Убрать") {
                    selection.wrappedValue = nil
                    preview = nil
                    status = nil
                }
                .accessibilityLabel("Убрать: \(title)")
            }
        }
    }

    private func chooseProfileFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = source.defaultFolder
        panel.message = "Выберите папку нужного профиля, например Default или Profile 1."
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }
            profileFolder = folder
            preview = nil
            status = nil
        }
    }

    private func chooseFile(_ message: String, contentTypes: [UTType], selection: Binding<URL?>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowedContentTypes = contentTypes
        panel.message = message
        panel.begin { response in
            guard response == .OK, let file = panel.url else { return }
            selection.wrappedValue = file
            preview = nil
            status = nil
        }
    }

    private func inspectImport() {
        let inputs = BrowserMigration.Inputs(source: source, directory: profileFolder,
                                             tabsFile: tabsFile, passwordsFile: passwordsFile)
        preview = nil
        run {
            preview = try await Task.detached { try BrowserMigration.inspect(inputs) }.value
            return "Данные подготовлены. Нажмите «Импортировать», чтобы добавить их в myBro."
        }
    }

    private func commitImport() {
        guard var migration = preview else { return }
        if !migration.contents.passwords.isEmpty {
            migration.contents.preferences[PasswordForms.autofillKey] = String(useAutofill)
        }
        run {
            let result = try browser.importProfile(migration.contents)
            preview = nil
            passwordsFile = nil
            return ([result.message] + migration.warnings).joined(separator: " ")
        }
    }

    private func showTabExporter() {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "Tools/TabExport")
        guard FileManager.default.fileExists(atPath: folder.appending(path: "manifest.json").path) else {
            status = "Папка Tools/TabExport доступна рядом с myBro.app в каталоге проекта."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private func chooseArchive() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let file = panel.url { operation = .restore(file) }
        }
    }

    private func restoreArchive(_ file: URL, passphrase: String) {
        run {
            let profile = try await Task.detached {
                let bytes = try ProfileArchive.read(file, limit: ProfileArchive.fileLimit)
                return try ProfileArchive.decode(bytes, passphrase: passphrase)
            }.value
            return try browser.importProfile(profile).message
        }
    }

    private func exportArchive(passphrase: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "myBro.mybroprofile"
        panel.begin { response in
            guard response == .OK, let file = panel.url else { return }
            run {
                let profile = try browser.exportProfile()
                try await Task.detached {
                    try ProfileArchive.encode(profile, passphrase: passphrase).write(to: file, options: .atomic)
                }.value
                return "Архив сохранён."
            }
        }
    }

    private func run(_ operation: @escaping @MainActor () async throws -> String) {
        guard !working else { return }
        working = true
        status = nil
        Task { @MainActor in
            defer { working = false }
            do { status = try await operation() }
            catch { status = error.localizedDescription }
        }
    }
}
