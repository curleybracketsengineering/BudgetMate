import Foundation

enum BudgetType: String, Codable, CaseIterable, Identifiable {
    case income
    case expense
    case saving
    case transfer
    case adjustment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .income: "Income"
        case .expense: "Expense"
        case .saving: "Saving"
        case .transfer: "Transfer"
        case .adjustment: "Adjustment"
        }
    }
}
