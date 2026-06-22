import Foundation

enum HolidayDetailPage: String, CaseIterable, Identifiable {
    case plan
    case map

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: "Plan"
        case .map: "Map"
        }
    }

    var systemImage: String {
        switch self {
        case .plan: "list.bullet"
        case .map: "map"
        }
    }
}
