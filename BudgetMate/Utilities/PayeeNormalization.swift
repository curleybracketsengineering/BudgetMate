import Foundation

enum PayeeNormalization {
    /// Group recurring items by merchant name; amounts clustered separately within 10%.
    static func normalize(_ payee: String) -> String {
        let raw = payee
            .components(separatedBy: "\t")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? payee

        var text = raw.uppercased()
        text = text.replacingOccurrences(of: "&AMP;", with: "&")
        text = text.replacingOccurrences(of: #"\*\s*\d+\*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\d{8,}"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.count < 4 {
            return raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    static func merchantKey(_ payee: String) -> String {
        let normalized = normalize(payee)
        guard !normalized.isEmpty else { return payee.uppercased() }
        let alias = canonicalMerchantAlias(for: normalized)
        return alias.isEmpty ? normalized : alias
    }

    static func matchKey(_ payee: String) -> String {
        normalize(payee)
    }

    static func displayName(from payee: String) -> String {
        let key = merchantKey(payee)
        let source = key.count >= 4 ? key : normalize(payee)
        let words = source.split(separator: " ").prefix(5).joined(separator: " ")
        let title = words.isEmpty ? payee : words
        return title.prefix(40).capitalized
    }

    static func amountsAreCompatible(_ a: Int, _ b: Int, tolerancePercent: Double = 0.10) -> Bool {
        let base = max(a, b)
        guard base > 0 else { return a == b }
        let tolerance = max(500, Int((Double(base) * tolerancePercent).rounded()))
        return abs(a - b) <= tolerance
    }

    static func clusterByAmount(
        _ rows: [ImportPreviewRow],
        tolerancePercent: Double = 0.10
    ) -> [[ImportPreviewRow]] {
        guard !rows.isEmpty else { return [] }
        let sorted = rows.sorted { $0.transaction.amountMinorUnits < $1.transaction.amountMinorUnits }
        var clusters: [[ImportPreviewRow]] = []

        for row in sorted {
            if let index = clusters.firstIndex(where: { cluster in
                let representative = medianAmount(in: cluster)
                return amountsAreCompatible(
                    row.transaction.amountMinorUnits,
                    representative,
                    tolerancePercent: tolerancePercent
                )
            }) {
                clusters[index].append(row)
            } else {
                clusters.append([row])
            }
        }

        return clusters
    }

    private static func medianAmount(in rows: [ImportPreviewRow]) -> Int {
        let amounts = rows.map(\.transaction.amountMinorUnits).sorted()
        let mid = amounts.count / 2
        if amounts.count.isMultiple(of: 2) {
            return (amounts[mid - 1] + amounts[mid]) / 2
        }
        return amounts[mid]
    }

    private static func canonicalMerchantAlias(for normalized: String) -> String {
        if normalized.contains("BT GROUP") || normalized.hasPrefix("BT ") || normalized == "BT" {
            return "BT"
        }
        if normalized.contains("BARCLAYS UK MTGES") || normalized.contains("BARCLAYS UK") {
            return "BARCLAYS MORTGAGE"
        }
        if normalized.contains("L&G INSURANCE") || normalized.contains("L & G INSURANCE") {
            return "L&G INSURANCE"
        }
        if normalized.contains("FORSAKRINGSKASSA") {
            return "FORSAKRINGSKASSA"
        }
        if normalized.contains("SEB PENSION") || normalized.contains("SEB PENSION OCH") {
            return "SEB PENSION"
        }
        if normalized.contains("ESSEX") && normalized.contains("WATER") {
            return "ESSEX WATER"
        }
        if normalized.contains("O2 ") || normalized.hasPrefix("O2 ") {
            return "O2"
        }
        if normalized.contains("PAYPAL PAYMENT") {
            return "PAYPAL"
        }
        if normalized.contains("CAPITAL ONE") {
            return "CAPITAL ONE"
        }
        if normalized.contains("VWFS") {
            return "VWFS"
        }
        if normalized.contains("TV LICENCE") {
            return "TV LICENCE"
        }
        if normalized.contains("ORACLE UK PENSION") || normalized.contains("ORACLE UK") {
            return "ORACLE PENSION"
        }
        return normalized
    }
}

enum PaymentMethodLabel {
    static func displayName(for subcategory: String) -> String {
        switch subcategory {
        case "Direct Debit": return "Direct Debit"
        case "Standing Order": return "Standing Order"
        case "Counter Credit": return "Bank credit"
        case "Debit", "Card Purchase": return "Card / debit"
        case "Credit": return "Credit"
        case "Transfer": return "Transfer"
        case "Bill Payment": return "Bill payment"
        case "Funds Transfer": return "Funds transfer"
        default: return subcategory.isEmpty ? "Other" : subcategory
        }
    }

    static func mostCommon(in rows: [ImportPreviewRow]) -> String {
        let counts = Dictionary(grouping: rows) { $0.transaction.subcategory }
            .mapValues(\.count)
        let winner = counts.max { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key > rhs.key }
            return lhs.value < rhs.value
        }
        return displayName(for: winner?.key ?? "Other")
    }
}
