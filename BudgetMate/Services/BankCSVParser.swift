import Foundation

enum BankCSVParser {
    enum ParseError: LocalizedError {
        case emptyFile
        case missingHeader
        case noTransactions

        var errorDescription: String? {
            switch self {
            case .emptyFile: "The file is empty."
            case .missingHeader: "Could not find a valid CSV header (Number, Date, Account, Amount, Subcategory, Memo)."
            case .noTransactions: "No transactions were found in the file."
            }
        }
    }

    private static let expectedHeader = ["number", "date", "account", "amount", "subcategory", "memo"]

    private static let ukDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    static func parse(data: Data) throws -> [BankTransactionRow] {
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ParseError.emptyFile
        }
        return try parse(content: content)
    }

    static func parse(content: String) throws -> [BankTransactionRow] {
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { throw ParseError.emptyFile }

        var startIndex = 0
        if let headerIndex = lines.firstIndex(where: { isHeaderLine($0) }) {
            startIndex = headerIndex + 1
        } else if !isHeaderLine(lines[0]) {
            startIndex = 0
        } else {
            throw ParseError.missingHeader
        }

        var rows: [BankTransactionRow] = []
        for line in lines.dropFirst(startIndex) {
            guard let fields = splitFields(line), fields.count >= 6 else { continue }
            guard let date = ukDateFormatter.date(from: fields[1]) else { continue }
            guard let amount = Double(fields[3]) else { continue }

            let minorUnits = Int((amount * 100).rounded())
            let memo = fields[5]
            let payee = extractPayee(from: memo)

            rows.append(BankTransactionRow(
                referenceNumber: fields[0],
                date: date,
                account: fields[2],
                signedAmountMinorUnits: minorUnits,
                subcategory: fields[4],
                payee: payee,
                memo: memo
            ))
        }

        guard !rows.isEmpty else { throw ParseError.noTransactions }
        return rows.sorted { $0.date > $1.date }
    }

    private static func isHeaderLine(_ line: String) -> Bool {
        let fields = line
            .lowercased()
            .split(separator: ",", maxSplits: 5, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 6 else { return false }
        return fields[0] == expectedHeader[0]
            && fields[1] == expectedHeader[1]
            && fields[2] == expectedHeader[2]
            && fields[3] == expectedHeader[3]
            && fields[4] == expectedHeader[4]
            && fields[5] == expectedHeader[5]
    }

    private static func splitFields(_ line: String) -> [String]? {
        var fields: [String] = []
        var current = ""
        var commaCount = 0

        for character in line {
            if character == ",", commaCount < 5 {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                commaCount += 1
            } else {
                current.append(character)
            }
        }

        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields.count >= 6 ? fields : nil
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
