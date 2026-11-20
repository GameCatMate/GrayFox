import Foundation

struct HistoryVisit: Codable, Identifiable {
    let id: UUID
    var title: String
    let url: URL
    let visitedAt: Date?

    var page: Page { Page(title: title, url: url) }

    init(page: Page, at date: Date) {
        id = UUID()
        title = page.title
        url = page.url
        visitedAt = date
    }

    private enum CodingKeys: String, CodingKey { case id, title, url, visitedAt }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decode(String.self, forKey: .title)
        url = try values.decode(URL.self, forKey: .url)
        visitedAt = try values.decodeIfPresent(Date.self, forKey: .visitedAt)
    }
}

struct BookmarkFolder: Codable, Identifiable {
    let id: UUID
    var name: String
    var parentID: UUID?
    var pages: [Page] = []

    init(name: String, parentID: UUID? = nil) {
        id = UUID()
        self.name = name
        self.parentID = parentID
    }
}

enum GroupTint: String, Codable, CaseIterable {
    case blue = "Синий"
    case purple = "Фиолетовый"
    case green = "Зелёный"
    case orange = "Оранжевый"
    case red = "Красный"
    case gray = "Серый"
}

enum ClearPeriod: String, CaseIterable {
    case hour = "За последний час"
    case day = "За последние 24 часа"
    case week = "За последнюю неделю"
    case month = "За последний месяц"
    case quarter = "За последние 3 месяца"
    case year = "За последний год"
    case all = "За всё время"

    func cutoff(now: Date = .now, calendar: Calendar = .current) -> Date {
        switch self {
        case .hour: now.addingTimeInterval(-3600)
        case .day: now.addingTimeInterval(-86_400)
        case .week: calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month: calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .quarter: calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .year: calendar.date(byAdding: .year, value: -1, to: now) ?? now
        case .all: .distantPast
        }
    }
}

