import Foundation

enum HolidayActivityListLayout: String, CaseIterable, Identifiable {
    case byType
    case byDay
    case calendar
    case map

    var id: String { rawValue }

    var title: String {
        switch self {
        case .byType: "By type"
        case .byDay: "By day"
        case .calendar: "Calendar"
        case .map: "Map"
        }
    }
}
