import Foundation

enum HolidayActivityListLayout: String, CaseIterable, Identifiable {
    case byType
    case byDate
    case byDay
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byType: "By type"
        case .byDate: "By date"
        case .byDay: "By day"
        case .calendar: "Calendar"
        }
    }
}
