import Foundation

enum BankImportFormat: String {
    case csv
    case qbo

    var displayName: String {
        switch self {
        case .csv: "CSV"
        case .qbo: "QBO (OFX)"
        }
    }
}

enum BankFileParser {
    enum ParseError: LocalizedError {
        case unsupportedFormat

        var errorDescription: String? {
            "This file format is not supported. Choose a bank CSV or QBO (OFX) export."
        }
    }

    struct ParseResult {
        let format: BankImportFormat
        let transactions: [BankTransactionRow]
    }

    static func parse(data: Data, filename: String? = nil) throws -> ParseResult {
        guard let content = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw BankCSVParser.ParseError.emptyFile
        }
        return try parse(content: content, filename: filename)
    }

    static func parse(content: String, filename: String? = nil) throws -> ParseResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let extensionHint = filename?.lowercased().hasSuffix(".qbo") == true ? BankImportFormat.qbo : nil

        if extensionHint == .qbo || isQBOFormat(trimmed) {
            let transactions = try BankQBOParser.parse(content: trimmed)
            return ParseResult(format: .qbo, transactions: transactions)
        }

        if isCSVFormat(trimmed) {
            let transactions = try BankCSVParser.parse(content: trimmed)
            return ParseResult(format: .csv, transactions: transactions)
        }

        throw ParseError.unsupportedFormat
    }

    private static func isQBOFormat(_ content: String) -> Bool {
        content.hasPrefix("OFXHEADER:")
            || content.contains("<OFX>")
            || content.contains("<STMTTRN>")
    }

    private static func isCSVFormat(_ content: String) -> Bool {
        let firstLine = content
            .components(separatedBy: .newlines)
            .first?
            .lowercased() ?? ""
        return firstLine.contains("number,date,account,amount")
            || content.contains(",\"")
    }
}
