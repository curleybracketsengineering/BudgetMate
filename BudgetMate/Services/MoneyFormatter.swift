import Foundation

enum MoneyFormatter {
    static func format(minorUnits: Int, currency: AppCurrency) -> String {
        let major = Double(minorUnits) / Double(currency.minorUnitDivisor)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.locale = Locale(identifier: currency.localeIdentifier)
        formatter.maximumFractionDigits = currency.minorUnitDivisor == 1 ? 0 : 2
        formatter.minimumFractionDigits = currency.minorUnitDivisor == 1 ? 0 : 2
        return formatter.string(from: NSNumber(value: major)) ?? "\(currency.symbol)\(major)"
    }

    static func parseMajorUnits(_ text: String, currency: AppCurrency) -> Int? {
        let cleaned = text
            .replacingOccurrences(of: currency.symbol, with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned) else { return nil }
        return Int((value * Double(currency.minorUnitDivisor)).rounded())
    }

    static func majorUnitsString(minorUnits: Int, currency: AppCurrency) -> String {
        let major = Double(minorUnits) / Double(currency.minorUnitDivisor)
        if currency.minorUnitDivisor == 1 {
            return String(format: "%.0f", major)
        }
        return String(format: "%.2f", major)
    }
}
