import Foundation

enum BudgetTileStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case archived
    case ignored

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: "Active"
        case .archived: "Archived"
        case .ignored: "Ignored"
        }
    }
}
