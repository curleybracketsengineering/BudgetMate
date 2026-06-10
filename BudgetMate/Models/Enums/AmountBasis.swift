import Foundation

enum AmountBasis: String, CaseIterable, Identifiable {
    case median
    case latest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .median: "Median"
        case .latest: "Latest"
        }
    }

    var perPaymentColumnTitle: String {
        switch self {
        case .median: "Median payment"
        case .latest: "Latest payment"
        }
    }
}
