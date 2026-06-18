import Foundation

enum BudgetCycleType: String, Codable, CaseIterable, Identifiable {
    case monthly
    case weekly
    case everyFourWeeks
    case tenMonthly
    case quarterly
    case twiceYearly
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
        case .twiceYearly: "Twice yearly"
        case .yearly: "Yearly"
        case .oneOff: "One-off"
        case .custom: "Custom"
        }
    }

    /// Suffix for list/detail amount labels, e.g. "£25.00 / month".
    var amountPeriodSuffix: String {
        switch self {
        case .monthly: " / month"
        case .weekly: " / week"
        case .everyFourWeeks: " / 4 weeks"
        case .tenMonthly, .twiceYearly, .custom: " / payment"
        case .quarterly: " / quarter"
        case .yearly: " / year"
        case .oneOff: ""
        }
    }
}
