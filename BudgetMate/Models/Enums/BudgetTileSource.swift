import Foundation

enum BudgetTileSource: String, Codable, CaseIterable, Identifiable {
    case manual
    case recurring
    case holiday
    case imported

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .recurring: "Recurring rule"
        case .holiday: "Holiday"
        case .imported: "Imported"
        }
    }
}
