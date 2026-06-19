import Foundation

enum HolidayStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case committed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .draft: "Draft"
        case .committed: "In monthly plan"
        }
    }
}
