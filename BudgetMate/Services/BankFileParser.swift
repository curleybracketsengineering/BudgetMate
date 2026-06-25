import Foundation

enum BankImportFormat: String {
    case csv
    case qbo
    case ofx

    var displayName: String {
        switch self {
        case .csv: "CSV"
        case .qbo: "QBO"
        case .ofx: "OFX"
        }
    }
}

enum BankFileParser {
    enum ParseError: LocalizedError {
        case unsupportedFormat

        var errorDescription: String? {
            "This file format is not supported. Choose a bank CSV, QBO, or OFX (Open Financial Exchange) export."
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
        let extensionHint = importFormat(from: filename)

        if extensionHint == .ofx || extensionHint == .qbo || isOFXFormat(trimmed) {
            let format = extensionHint ?? .ofx
            let transactions = try BankQBOParser.parse(content: trimmed)
            return ParseResult(format: format, transactions: transactions)
        }

        if isCSVFormat(trimmed) {
            let transactions = try BankCSVParser.parse(content: trimmed)
            return ParseResult(format: .csv, transactions: transactions)
        }

        throw ParseError.unsupportedFormat
    }

    private static func importFormat(from filename: String?) -> BankImportFormat? {
        guard let lowercased = filename?.lowercased() else { return nil }
        if lowercased.hasSuffix(".ofx") { return .ofx }
        if lowercased.hasSuffix(".qbo") { return .qbo }
        return nil
    }

    private static func isOFXFormat(_ content: String) -> Bool {
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
