import Foundation

enum ImportPaymentMethodFilter: String, CaseIterable, Identifiable, Hashable {
    case directDebit
    case standingOrder
    case cardDebit
    case bankCredit
    case credit
    case transfer
    case billPayment
    case fundsTransfer
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .directDebit: "Direct Debit"
        case .standingOrder: "Standing Order"
        case .cardDebit: "Card / debit"
        case .bankCredit: "Bank credit"
        case .credit: "Credit"
        case .transfer: "Transfer"
        case .billPayment: "Bill payment"
        case .fundsTransfer: "Funds transfer"
        case .other: "Other"
        }
    }

    static let displayOrder: [ImportPaymentMethodFilter] = [
        .directDebit,
        .standingOrder,
        .cardDebit,
        .bankCredit,
        .billPayment,
        .credit,
        .transfer,
        .fundsTransfer,
        .other
    ]

    static func from(subcategory: String) -> ImportPaymentMethodFilter {
        switch subcategory {
        case "Direct Debit": return .directDebit
        case "Standing Order": return .standingOrder
        case "Debit", "Card Purchase": return .cardDebit
        case "Counter Credit": return .bankCredit
        case "Credit": return .credit
        case "Transfer": return .transfer
        case "Bill Payment": return .billPayment
        case "Funds Transfer": return .fundsTransfer
        default: return .other
        }
    }

    func matches(subcategory: String) -> Bool {
        Self.from(subcategory: subcategory) == self
    }

    func matches(paymentMethod: String) -> Bool {
        if self == .other {
            let knownTitles = Set(Self.displayOrder.filter { $0 != .other }.map(\.title))
            return !knownTitles.contains(paymentMethod)
        }
        return paymentMethod == title
    }
}
