import Foundation

enum ImportFlowFocus: String, CaseIterable, Identifiable {
    case incoming
    case outgoing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .incoming: "Incoming"
        case .outgoing: "Outgoing"
        }
    }

    func includes(budgetType: BudgetType) -> Bool {
        switch self {
        case .incoming: budgetType == .income
        case .outgoing: budgetType == .expense || budgetType == .saving
        }
    }
}
