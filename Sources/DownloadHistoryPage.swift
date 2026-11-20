import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DownloadHistoryPage: View {
    @ObservedObject var downloads: Downloads
    let isPrivate: Bool
    let showPage: (InternalPage) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var search = ""
    @State private var hidesCompleted = false
    @State private var openingError: String?

    private let locale = Locale(identifier: "ru_RU")
    private let calendar = Calendar.current

    private var card: Color {
        colorScheme == .dark ? Color(white: 0.09) : Color(nsColor: .windowBackgroundColor)
    }

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = downloads.items.filter { item in
            (!hidesCompleted || !item.isComplete) &&
                (query.isEmpty || item.name.localizedCaseInsensitiveContains(query) ||
                    item.sourceURL?.absoluteString.localizedCaseInsensitiveContains(query) == true)
        }
        let byMonth = Dictionary(grouping: visible) { item in
            calendar.dateInterval(of: .month, for: item.startedAt)?.start ??
                calendar.startOfDay(for: item.startedAt)
        }
        let months = byMonth.keys.sorted(by: >)

        VStack(spacing: 16) {
            navigation
            ScrollViewReader { list in
                HStack(alignment: .top, spacing: 8) {
                    sidebar(months: months, list: list)
                        .frame(minWidth: 156, idealWidth: 232, maxWidth: 232)
                        .background(card, in: RoundedRectangle(cornerRadius: 12))
                    timeline(months: months, byMonth: byMonth, query: query)
                        .background(card, in: RoundedRectangle(cornerRadius: 12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: 1030)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? .black : Color(nsColor: .underPageBackgroundColor))
    }

    private var navigation: some View {
        HStack(spacing: 4) {
            if !isPrivate {
                navigationButton("Закладки", page: .bookmarks)
            }
            Text("Загрузки")
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.primary.opacity(0.11), in: Capsule())
                .accessibilityAddTraits(.isSelected)
            if !isPrivate {
                navigationButton("История", page: .history)
            }
            navigationButton("Настройки", page: .settings)
        }
        .font(.system(size: 13))
    }

    private func navigationButton(_ title: String, page: InternalPage) -> some View {
        Button { showPage(page) } label: {
            Text(title).padding(.horizontal, 12).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private func sidebar(months: [Date], list: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Поиск", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .padding([.top, .horizontal], 16)

            Divider().padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(months, id: \.self) { month in
                        sidebarButton(monthTitle(month)) {
                            list.scrollTo(month, anchor: .top)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: .infinity)

            Divider()
            VStack(alignment: .leading, spacing: 2) {
                sidebarButton("Открыть папку") {
                    let opened = (try? NSWorkspace.shared.open(downloads.destinationDirectory())) == true
                    openingError = opened ? nil : "Не удалось открыть папку загрузок."
                }
                sidebarButton(hidesCompleted ? "Показать загруженные" : "Скрыть загруженные") {
                    hidesCompleted.toggle()
                }
                .disabled(!hidesCompleted && !downloads.items.contains(where: \.isComplete))
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(maxHeight: .infinity)
    }

    private func sidebarButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func timeline(months: [Date], byMonth: [Date: [DownloadItem]], query: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let openingError {
                Text(openingError).foregroundStyle(.red).padding(16)
            }
            if months.isEmpty {
                Text(query.isEmpty
                     ? (hidesCompleted ? "Нет незавершённых загрузок." : "Загрузок пока нет.")
                     : "Ничего не найдено.")
                    .foregroundStyle(.secondary)
                    .padding(24)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(months, id: \.self) { month in
                            Section {
                                days(byMonth[month] ?? [])
                            } header: {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text(monthTitle(month))
                                        .font(.system(size: 19, weight: .semibold))
                                        .accessibilityAddTraits(.isHeader)
                                    Divider()
                                }
                                .padding([.top, .horizontal], 24)
                                .background(card)
                            }
                            .id(month)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func days(_ items: [DownloadItem]) -> some View {
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.startedAt) }
        return ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
            Text(day.formatted(.dateTime.day().month(.wide).locale(locale)))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 28)
                .padding(.bottom, 8)
                .padding(.leading, 12)
            ForEach((grouped[day] ?? []).sorted { $0.startedAt > $1.startedAt }) { item in
                DownloadTimelineRow(
                    item: item,
                    cancel: { downloads.cancel(item.id) },
                    remove: { downloads.removeFromHistory(item.id) },
                    open: { url in
                        openingError = NSWorkspace.shared.open(url) ? nil : "Не удалось открыть «\(item.name)»."
                    }
                )
            }
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let month = date.formatted(.dateTime.month(.wide).locale(locale)).capitalized(with: locale)
        let year = calendar.component(.year, from: date)
        return year == calendar.component(.year, from: .now) ? month : "\(month) \(year)"
    }
}

private struct DownloadTimelineRow: View {
    let item: DownloadItem
    let cancel: () -> Void
    let remove: () -> Void
    let open: (URL) -> Void

    @State private var hovered = false
    @FocusState private var focusedAction: Action?

    private enum Action: Hashable { case file, reveal, more, cancel }

    var body: some View {
        let file = item.localFile
        let type = UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data
        let icon = file.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: type)
        HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                filename(file: file)
                if let source = item.sourceURL {
                    Text(verbatim: source.absoluteString)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                switch item.state {
                case .downloading(let progress):
                    TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                        if progress.isIndeterminate {
                            Text("Скачивается").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ProgressView(value: progress.fractionCompleted).accessibilityLabel("Ход загрузки")
                        }
                    }
                case .failed(let message):
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                case .complete where file == nil:
                    Text("Файл удалён").font(.caption).foregroundStyle(.secondary)
                case .complete:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions(file: file)
                .opacity(hovered || focusedAction != nil ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 64)
        .background(.primary.opacity(hovered || focusedAction != nil ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu { actionsMenu(file: file) }
    }

    private func filename(file: URL?) -> some View {
        HStack(spacing: 6) {
            if item.isComplete, let file {
                Button { open(file) } label: { name }
                    .buttonStyle(.plain)
                    .focused($focusedAction, equals: .file)
            } else {
                name
            }
            if item.isComplete, let file,
               let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                Text(Int64(size).formatted(.byteCount(style: .file).locale(Locale(identifier: "ru_RU"))))
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .fixedSize()
            }
        }
    }

    private var name: some View {
        Text(item.name)
            .font(.system(size: 14, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .help(item.name)
    }

    @ViewBuilder
    private func actions(file: URL?) -> some View {
        HStack(spacing: 16) {
            if case .downloading = item.state {
                Button("Отменить", action: cancel)
                    .focused($focusedAction, equals: .cancel)
            } else {
                if let file {
                    Button("Показать в папке") { reveal(file) }
                        .focused($focusedAction, equals: .reveal)
                }
                Menu("Ещё") { actionsMenu(file: file) }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .focused($focusedAction, equals: .more)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(nsColor: .linkColor))
        .font(.system(size: 13))
        .fixedSize()
    }

    @ViewBuilder
    private func actionsMenu(file: URL?) -> some View {
        if case .downloading = item.state {
            Button("Отменить", action: cancel)
        } else {
            if let file {
                if item.isComplete { Button("Открыть файл") { open(file) } }
                Button("Показать в папке") { reveal(file) }
            }
            Button("Удалить из истории", role: .destructive, action: remove)
        }
    }

    private func reveal(_ file: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }
}
