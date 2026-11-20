import SwiftUI

struct BookmarkBar: View {
    @ObservedObject var browser: Browser
    let showsIcons: Bool
    let addBookmark: () -> Void
    @State private var asksForFolder = false
    @State private var folderName = ""

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(browser.bookmarkFolders.filter { $0.parentID == nil }) { folder in
                    Menu {
                        BookmarkFolderContents(browser: browser, folder: folder)
                    } label: {
                        Label(folder.name, systemImage: "folder").lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                    .contextMenu {
                        Button("Удалить папку, сохранив содержимое") {
                            browser.removeBookmarkFolder(folder.id)
                        }
                    }
                }
                ForEach(browser.data.bookmarks) { page in
                    Button { browser.open(page) } label: {
                        Group {
                            if showsIcons { Label(page.title, systemImage: "globe") }
                            else { Text(page.title) }
                        }
                        .lineLimit(1)
                        .frame(maxWidth: 160)
                    }
                    .buttonStyle(.borderless)
                    .help(page.url.absoluteString)
                    .contextMenu {
                        Button("Удалить закладку") { browser.removeBookmark(page) }
                    }
                }
                Menu {
                    Button("Добавить закладку…", action: addBookmark)
                        .disabled(browser.active?.saved.page == nil)
                    Button("Новая папка…") { newFolder() }
                } label: {
                    Label("Добавить на панель закладок", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .frame(height: 29)
        .background(.background)
        .accessibilityLabel("Панель закладок")
        .contextMenu {
            Button("Добавить закладку…", action: addBookmark)
                .disabled(browser.active?.saved.page == nil)
            Button("Новая папка…") { newFolder() }
        }
        .alert("Новая папка закладок", isPresented: $asksForFolder) {
            TextField("Название папки", text: $folderName)
            Button("Отмена", role: .cancel) {}
            Button("Создать") { _ = browser.createBookmarkFolder(folderName) }
                .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func newFolder() {
        folderName = ""
        asksForFolder = true
    }
}

struct BookmarkEditor: View {
    @ObservedObject var browser: Browser
    let page: Page
    let openManager: (() -> Void)?
    let dismiss: () -> Void
    @State private var title: String
    @State private var folder: UUID?
    @State private var isCreatingFolder = false
    @State private var folderName = ""

    init(browser: Browser, page: Page, openManager: (() -> Void)? = nil, dismiss: @escaping () -> Void) {
        self.browser = browser
        self.page = page
        self.openManager = openManager
        self.dismiss = dismiss
        _title = State(initialValue: browser.allBookmarks.first { $0.url == page.url }?.title ?? page.title)
        _folder = State(initialValue: browser.bookmarkFolder(containing: page))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Закладка").font(.headline)
            TextField("Название", text: $title)
            Picker("Папка", selection: $folder) {
                Text("Панель закладок").tag(nil as UUID?)
                ForEach(browser.bookmarkFolders) { option in
                    Text(folderPath(option)).tag(Optional(option.id))
                }
            }
            if isCreatingFolder {
                HStack {
                    TextField("Название папки", text: $folderName)
                    Button("Создать") {
                        folder = browser.createBookmarkFolder(folderName, parent: folder)
                        isCreatingFolder = false
                        folderName = ""
                    }
                    .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Button("Новая папка…") { isCreatingFolder = true }
            }
            HStack {
                if browser.allBookmarks.contains(where: { $0.url == page.url }) {
                    Button("Удалить", role: .destructive) {
                        browser.removeBookmark(page)
                        dismiss()
                    }
                }
                Spacer()
                Button("Отмена", action: dismiss)
                Button("Сохранить") {
                    browser.saveBookmark(Page(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                              url: page.url), folder: folder)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let openManager {
                Divider()
                Button {
                    dismiss()
                    openManager()
                } label: {
                    Label("Открыть менеджер закладок", systemImage: "macwindow")
                }
                .buttonStyle(.link)
            }
        }
        .padding(12)
        .frame(width: 360)
    }

    private func folderPath(_ folder: BookmarkFolder) -> String {
        var path = [folder.name]
        var parentID = folder.parentID
        var seen = Set([folder.id])
        while let id = parentID, seen.insert(id).inserted,
              let parent = browser.bookmarkFolders.first(where: { $0.id == id }) {
            path.append(parent.name)
            parentID = parent.parentID
        }
        return path.reversed().joined(separator: " / ")
    }
}

private struct BookmarkFolderContents: View {
    @ObservedObject var browser: Browser
    let folder: BookmarkFolder

    var body: some View {
        let children = browser.bookmarkFolders.filter { $0.parentID == folder.id }
        if children.isEmpty && folder.pages.isEmpty { Text("Папка пуста") }
        ForEach(children) { child in
            Menu(child.name) {
                BookmarkFolderContents(browser: browser, folder: child)
            }
        }
        ForEach(folder.pages) { page in
            Button(page.title) { browser.open(page) }
        }
    }
}

private struct BookmarkNode: Identifiable {
    enum ID: Hashable {
        case folder(UUID)
        case page(URL)
    }

    let id: ID
    let title: String
    let children: [BookmarkNode]?

    @MainActor static func nodes(in browser: Browser) -> [BookmarkNode] {
        let childrenByParent = Dictionary(grouping: browser.bookmarkFolders, by: \.parentID)
        func build(_ parent: UUID?, pages: [Page]) -> [BookmarkNode] {
            let folders = (childrenByParent[parent] ?? []).map { folder in
                BookmarkNode(id: .folder(folder.id), title: folder.name,
                             children: build(folder.id, pages: folder.pages))
            }
            return folders + pages.map { BookmarkNode(id: .page($0.url), title: $0.title, children: nil) }
        }
        return build(nil, pages: browser.data.bookmarks)
    }
}

struct BookmarkManager: View {
    static let windowID = "bookmarks"

    private enum FolderEdit {
        case create(parent: UUID?)
        case rename(UUID)
    }

    @ObservedObject var browser: Browser
    @Environment(\.openWindow) private var openWindow
    @State private var selected: BookmarkNode.ID?
    @State private var editedPage: Page?
    @State private var folderEdit: FolderEdit = .create(parent: nil)
    @State private var folderName = ""
    @State private var showingFolderEditor = false

    var body: some View {
        let nodes = BookmarkNode.nodes(in: browser)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Избранное").font(.title2.weight(.semibold))
                Spacer()
                Button("Новая папка…") { editFolder(.create(parent: selectedFolder)) }
                Button("Изменить…") {
                    if let selected { edit(selected) }
                }
                .disabled(selected == nil)
                Button("Удалить", role: .destructive) {
                    if let selected { remove(selected) }
                }
                .disabled(selected == nil)
            }
            if nodes.isEmpty {
                Text("Избранное пока пусто.").foregroundStyle(.secondary)
                Spacer()
            } else {
                List(selection: $selected) {
                    OutlineGroup(nodes, children: \.children) { node in
                        row(node)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 860, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editedPage) { page in
            BookmarkEditor(browser: browser, page: page) { editedPage = nil }
        }
        .alert(folderPrompt, isPresented: $showingFolderEditor) {
            TextField("Название папки", text: $folderName)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") {
                switch folderEdit {
                case let .create(parent):
                    if let id = browser.createBookmarkFolder(folderName, parent: parent) {
                        selected = .folder(id)
                    }
                case let .rename(id):
                    _ = browser.renameBookmarkFolder(id, to: folderName)
                }
            }
            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var selectedFolder: UUID? {
        switch selected {
        case let .folder(id): return id
        case let .page(url):
            return browser.allBookmarks.first { $0.url == url }.flatMap { browser.bookmarkFolder(containing: $0) }
        case nil: return nil
        }
    }

    private var folderPrompt: String {
        if case .rename = folderEdit { return "Переименовать папку" }
        return "Новая папка"
    }

    private func row(_ node: BookmarkNode) -> some View {
        HStack {
            Label(node.title, systemImage: node.children == nil ? "globe" : "folder")
            Spacer()
            if case let .page(url) = node.id {
                Text(url.host ?? url.absoluteString).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .tag(node.id)
        .contextMenu {
            switch node.id {
            case let .folder(id):
                Button("Новая вложенная папка…") { editFolder(.create(parent: id)) }
                Button("Переименовать…") { edit(node.id) }
                Button("Удалить папку, сохранив содержимое") { remove(node.id) }
            case let .page(url):
                Button("Открыть в новой вкладке") {
                    if let page = browser.allBookmarks.first(where: { $0.url == url }) {
                        browser.newTab(SavedTab(page: page, group: browser.activeGroup))
                        openWindow(id: "browser")
                    }
                }
                Button("Переименовать или переместить…") { edit(node.id) }
                Button("Удалить закладку", role: .destructive) { remove(node.id) }
            }
        }
    }

    private func edit(_ selection: BookmarkNode.ID) {
        switch selection {
        case let .folder(id): editFolder(.rename(id))
        case let .page(url): editedPage = browser.allBookmarks.first { $0.url == url }
        }
    }

    private func editFolder(_ mode: FolderEdit) {
        folderEdit = mode
        if case let .rename(id) = mode {
            folderName = browser.bookmarkFolders.first { $0.id == id }?.name ?? ""
        } else {
            folderName = ""
        }
        showingFolderEditor = true
    }

    private func remove(_ selection: BookmarkNode.ID) {
        switch selection {
        case let .folder(id): browser.removeBookmarkFolder(id)
        case let .page(url):
            if let page = browser.allBookmarks.first(where: { $0.url == url }) {
                browser.removeBookmark(page)
            }
        }
        if selected == selection { selected = nil }
    }
}


