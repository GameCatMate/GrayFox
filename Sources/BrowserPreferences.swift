import Foundation

enum BrowserPreference {
    static let theme = "browser-theme"
    static let startSearch = "start-page-search"
    static let startTiles = "start-page-bookmarks"
    static let startClock = "start-page-clock"
    static let bookmarkBar = "bookmark-bar-visibility"
    static let bookmarkIcons = "bookmark-bar-icons"
    static let restoreTabs = "restore-tabs"
    static let extraStartTab = "extra-start-tab"
    static let reuseExternalTab = "reuse-external-tab"
    static let pageZoom = "default-page-zoom"
    static let minimumFontSize = "minimum-web-font-size"
    static let previewPDF = "preview-pdf"
    static let allowCamera = "allow-camera"
    static let allowMicrophone = "allow-microphone"
    static let pageSnapshots = "page-snapshots"
    static let reduceMotion = "reduce-browser-motion"
    static let downloadsFolder = "downloads-folder"
    static let askDownloadFolder = "ask-download-folder"

    static let zoomLevels = [50, 67, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300]
    static let fontSizes = [0, 12, 14, 16, 18, 20, 24]

    static let booleanKeys = [
        startSearch, startTiles, startClock, bookmarkIcons, restoreTabs, extraStartTab, reuseExternalTab,
        previewPDF, allowCamera, allowMicrophone, pageSnapshots, reduceMotion, askDownloadFolder
    ]

    static func enabled(_ defaults: UserDefaults, _ key: String, fallback: Bool = true) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    static func pageZoom(in defaults: UserDefaults) -> Double {
        let level = defaults.integer(forKey: pageZoom)
        return zoomLevels.contains(level) ? Double(level) / 100 : 1
    }

    static func minimumFont(in defaults: UserDefaults) -> CGFloat {
        let size = defaults.integer(forKey: minimumFontSize)
        return fontSizes.contains(size) ? CGFloat(size) : 0
    }
}

enum BrowserTheme: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "Как в системе"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }
}

enum BookmarkBarVisibility: String, CaseIterable {
    case always, newTab, hidden

    var title: String {
        switch self {
        case .always: "На всех страницах"
        case .newTab: "На новой вкладке"
        case .hidden: "Скрыта"
        }
    }
}
