import Foundation

/// Supported display currencies. Amounts are stored in minor units (e.g. pence, cents).
/// JPY uses minorUnitDivisor 1 (whole yen).
enum AppCurrency: String, Codable, CaseIterable, Identifiable {
    case GBP
    case USD
    case EUR
    case AUD
    case CAD
    case NZD
    case CHF
    case JPY

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .GBP: "British Pound (£)"
        case .USD: "US Dollar ($)"
        case .EUR: "Euro (€)"
        case .AUD: "Australian Dollar (A$)"
        case .CAD: "Canadian Dollar (C$)"
        case .NZD: "New Zealand Dollar (NZ$)"
        case .CHF: "Swiss Franc (CHF)"
        case .JPY: "Japanese Yen (¥)"
        }
    }

    var symbol: String {
        switch self {
        case .GBP: "£"
        case .USD: "$"
        case .EUR: "€"
        case .AUD: "A$"
        case .CAD: "C$"
        case .NZD: "NZ$"
        case .CHF: "CHF "
        case .JPY: "¥"
        }
    }

    /// Divisor to convert minor units to major units for display.
    var minorUnitDivisor: Int {
        switch self {
        case .JPY: 1
        default: 100
        }
    }

    var localeIdentifier: String {
        switch self {
        case .GBP: "en_GB"
        case .USD: "en_US"
        case .EUR: "de_DE"
        case .AUD: "en_AU"
        case .CAD: "en_CA"
        case .NZD: "en_NZ"
        case .CHF: "de_CH"
        case .JPY: "ja_JP"
        }
    }
}
