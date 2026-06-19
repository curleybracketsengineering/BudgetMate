import Foundation

enum HolidayActivityEstimateSource: String, Codable, CaseIterable, Identifiable {
    case manual
    case aiSuggested

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .aiSuggested: "AI suggested"
        }
    }
}
