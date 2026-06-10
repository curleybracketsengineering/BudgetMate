import Foundation

enum BudgetCycleType: String, Codable, CaseIterable, Identifiable {
    case monthly
    case weekly
    case everyFourWeeks
    case tenMonthly
    case quarterly
    case yearly
    case oneOff
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monthly: "Monthly"
        case .weekly: "Weekly"
        case .everyFourWeeks: "Every 4 weeks"
        case .tenMonthly: "10 months per year"
        case .quarterly: "Quarterly"
        case .yearly: "Yearly"
        case .oneOff: "One-off"
        case .custom: "Custom"
        }
    }
}
