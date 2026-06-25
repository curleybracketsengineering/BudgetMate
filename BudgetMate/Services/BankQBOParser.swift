import Foundation

/// Parses Quicken/QBO and Open Financial Exchange (OFX) bank exports in OFX 1.x SGML format (OFXHEADER + `<OFX>` body).
enum BankQBOParser {
    enum ParseError: LocalizedError {
        case emptyFile
        case invalidFormat
        case noTransactions

        var errorDescription: String? {
            switch self {
            case .emptyFile: "The file is empty."
            case .invalidFormat: "Could not find OFX transaction data in this file."
            case .noTransactions: "No transactions were found in this file."
            }
        }
    }

    static func parse(data: Data) throws -> [BankTransactionRow] {
        guard let content = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw ParseError.emptyFile
        }
        return try parse(content: content)
    }

    static func parse(content: String) throws -> [BankTransactionRow] {
        let body = ofxBody(from: content)
        guard body.contains("<STMTTRN>") else { throw ParseError.invalidFormat }

        let account = tagValue("ACCTID", in: body) ?? "Bank account"
        let currencyCode = tagValue("CURDEF", in: body) ?? "GBP"
        let blocks = extractBlocks(named: "STMTTRN", in: body)

        var rows: [BankTransactionRow] = []
        for block in blocks {
            guard let amountText = tagValue("TRNAMT", in: block),
                  let amount = Double(amountText) else { continue }
            guard let posted = tagValue("DTPOSTED", in: block),
                  let date = parseOFXDate(posted) else { continue }

            let trnType = tagValue("TRNTYPE", in: block) ?? "OTHER"
            let fitId = tagValue("FITID", in: block) ?? UUID().uuidString
            let name = decodeEntities(tagValue("NAME", in: block) ?? tagValue("MEMO", in: block) ?? "Transaction")
            let payee = extractPayee(from: name)
            let subcategory = mapTransactionType(trnType, amount: amount)

            let minorUnits = toMinorUnits(amount, currencyCode: currencyCode)

            rows.append(BankTransactionRow(
                referenceNumber: fitId,
                date: date,
                account: account,
                signedAmountMinorUnits: minorUnits,
                subcategory: subcategory,
                payee: payee,
                memo: name
            ))
        }

        guard !rows.isEmpty else { throw ParseError.noTransactions }
        return rows.sorted { $0.date > $1.date }
    }

    // MARK: - OFX SGML helpers

    private static func ofxBody(from content: String) -> String {
        if let range = content.range(of: "<OFX>", options: .caseInsensitive) {
            return String(content[range.lowerBound...])
        }
        return content
    }

    private static func extractBlocks(named tag: String, in content: String) -> [String] {
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.matches(in: content, range: range).compactMap { match in
            guard let blockRange = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[blockRange])
        }
    }

    private static func tagValue(_ tag: String, in content: String) -> String? {
        let pattern = "<\(tag)>([^<\n\r]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              let valueRange = Range(match.range(at: 1), in: content) else { return nil }
        return String(content[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseOFXDate(_ value: String) -> Date? {
        let digits = value.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }
        let year = Int(digits.prefix(4)) ?? 0
        let month = Int(digits.dropFirst(4).prefix(2)) ?? 0
        let day = Int(digits.dropFirst(6).prefix(2)) ?? 0
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }

    private static func toMinorUnits(_ amount: Double, currencyCode: String) -> Int {
        let divisor = currencyCode == "JPY" ? 1.0 : 100.0
        return Int((amount * divisor).rounded())
    }

    private static func mapTransactionType(_ trnType: String, amount: Double) -> String {
        switch trnType.uppercased() {
        case "DIRECTDEBIT", "REPEATPMT": return "Direct Debit"
        case "DIRECTDEP": return "Counter Credit"
        case "PAYMENT": return "Standing Order"
        case "DEBIT", "CHECK", "ATM", "POS": return "Debit"
        case "CREDIT", "INT", "DIV": return "Credit"
        case "XFER", "TRANSFER": return "Transfer"
        default:
            return amount >= 0 ? "Counter Credit" : "Debit"
        }
    }

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    private static func extractPayee(from memo: String) -> String {
        let primary = memo
            .components(separatedBy: "\t")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? memo

        return primary
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
