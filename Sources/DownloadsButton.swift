import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DownloadsButton: View {
    @ObservedObject var downloads: Downloads
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(BrowserPreference.reduceMotion) private var reduceMotion = false
    let showRecent: () -> Void

    private var active: [Progress] {
        downloads.items.compactMap { item in
            if case let .downloading(progress) = item.state { return progress }
            return nil
        }
    }

    var body: some View {
        let active = active
        TimelineView(.animation(minimumInterval: 0.15, paused: active.isEmpty)) { tick in
            let known = active.filter { !$0.isIndeterminate }
            let fraction = !active.isEmpty && known.count == active.count
                ? known.reduce(0.0) { $0 + $1.fractionCompleted } / Double(known.count) : nil
            Button(action: showRecent) {
                Image(systemName: "arrow.down")
                    .font(.system(size: AddressToolbarMetrics.symbolSize, weight: .bold))
                    .frame(width: AddressToolbarMetrics.controlSize, height: AddressToolbarMetrics.controlSize)
                    .overlay {
                        if !active.isEmpty {
                            Circle().stroke(Color.accentColor.opacity(0.24), lineWidth: 1.5)
                            Circle().trim(from: 0, to: fraction ?? 0.24)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                                .rotationEffect(.degrees(indicatorAngle(fraction: fraction, date: tick.date)))
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Загрузки")
            .accessibilityLabel("Загрузки")
            .accessibilityValue(active.isEmpty ? "" : fraction.map {
                $0.formatted(.percent.precision(.fractionLength(0)))
            } ?? "Скачивается")
        }
        .anchorPreference(key: DownloadsAnchor.self, value: .bounds) { $0 }
    }

    private func indicatorAngle(fraction: Double?, date: Date) -> Double {
        guard fraction == nil, !systemReduceMotion, !reduceMotion else { return -90 }
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360 - 90
    }
}

private struct DownloadsAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct DownloadsPopover: ViewModifier {
    @ObservedObject var downloads: Downloads
    @Binding var isPresented: Bool
    let openDownloads: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var panelFocused: Bool
    @State private var hidesCompleted = false

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(DownloadsAnchor.self) { anchor in
            if isPresented, let anchor {
                GeometryReader { geometry in
                    let button = geometry[anchor]
                    let top = button.maxY + 12
                    let inset: CGFloat = 8
                    let background = colorScheme == .dark
                        ? Color(white: 0.15) : Color(nsColor: .windowBackgroundColor)
                    ZStack(alignment: .topTrailing) {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { isPresented = false }
                            .accessibilityHidden(true)
                        RecentDownloads(
                            downloads: downloads, hidesCompleted: $hidesCompleted,
                            maximumListHeight: max(68, geometry.size.height - top - 136)
                        ) {
                            isPresented = false
                            openDownloads()
                        }
                        .background(background, in: RoundedRectangle(cornerRadius: 14))
                        .background(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 2).fill(background)
                                .frame(width: 16, height: 16)
                                .rotationEffect(.degrees(45))
                                .offset(x: button.midX - (geometry.size.width - inset - 8), y: -8)
                                .accessibilityHidden(true)
                        }
                        .shadow(color: .black.opacity(0.24), radius: 9, y: 3)
                        .focusable()
                        .focusEffectDisabled()
                        .focused($panelFocused)
                        .onAppear { panelFocused = true }
                        .onKeyPress(.escape) {
                            isPresented = false
                            return .handled
                        }
                        .padding(.top, top)
                        .padding(.trailing, inset)
                    }
                    .onExitCommand { isPresented = false }
                }
            }
        }
    }
}

private struct RecentDownloads: View {
    @ObservedObject var downloads: Downloads
    @Binding var hidesCompleted: Bool
    let maximumListHeight: CGFloat
    let openDownloads: () -> Void
    @State private var openingError: String?
    private let rowHeight: CGFloat = 68

    private var items: [DownloadItem] {
        Array(downloads.items.lazy.filter { !hidesCompleted || !isComplete($0) }.prefix(9))
    }

    var body: some View {
        let items = items
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Загрузки").font(.system(size: 24, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Открыть папку") { openFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(nsColor: .linkColor))
            }
            if let openingError {
                Text(openingError).font(.caption).foregroundStyle(.red)
            }
            if items.isEmpty {
                Text(hidesCompleted ? "Нет незавершённых загрузок." : "Загрузок пока нет.")
                    .foregroundStyle(.secondary)
                    .frame(height: rowHeight, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                        }
                    }
                }
                .frame(height: min(CGFloat(items.count) * rowHeight, maximumListHeight))
            }
            HStack(spacing: 24) {
                Button(action: openDownloads) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .help("Открыть все загрузки")
                .accessibilityLabel("Открыть все загрузки")
                if downloads.items.contains(where: isComplete) {
                    Button(hidesCompleted ? "Показать загруженные" : "Скрыть загруженные") {
                        hidesCompleted.toggle()
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(Color(nsColor: .linkColor))
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 376)
    }

    private func isComplete(_ item: DownloadItem) -> Bool {
        if case .complete = item.state { return true }
        return false
    }

    @ViewBuilder
    private func row(_ item: DownloadItem) -> some View {
        let file = item.localFile
        if isComplete(item), let file {
            Button {
                openingError = NSWorkspace.shared.open(file) ? nil : "Не удалось открыть «\(item.name)»."
            } label: {
                rowContent(item, file: file)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            }
        } else {
            rowContent(item, file: file)
        }
    }

    private func rowContent(_ item: DownloadItem, file: URL?) -> some View {
        let itemType = UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data
        let icon = file.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: itemType)
        return HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                status(item, file: file)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func status(_ item: DownloadItem, file: URL?) -> some View {
        switch item.state {
        case let .downloading(progress):
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                Text(progress.isIndeterminate ? "Скачивается" : progress.fractionCompleted.formatted(
                    .percent.precision(.fractionLength(0))
                ))
            }
        case .complete:
            if let file {
                let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
                Text(size.map { Int64($0).formatted(.byteCount(style: .file)
                    .locale(Locale(identifier: "ru_RU"))) } ?? "Загружено")
            } else {
                Text("Файл удалён")
            }
        case let .failed(message):
            Text(message)
        }
    }

    private func openFolder() {
        do {
            openingError = NSWorkspace.shared.open(try downloads.destinationDirectory())
                ? nil : "Не удалось открыть папку загрузок."
        } catch {
            openingError = "Не удалось открыть папку загрузок."
        }
    }
}

