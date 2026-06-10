import Foundation
import Observation

/// Holds in-progress bank import state so it survives sidebar navigation.
@Observable
final class ImportSessionStore {
    var previewRows: [ImportPreviewRow] = []
    var excludedRows: [ImportPreviewRow] = []
    var budgetSuggestions: [BudgetSuggestion] = []
    var typicalMonth = TypicalMonthSummary()
    var importedFileName: String?
    var importedFormat: BankImportFormat?
    var parseError: String?
    var importMessage: String?
    var flowFocus: ImportFlowFocus = .incoming
    var payeeNotes: [String: PayeeNote] = [:]
    var amountBasis: AmountBasis = .median

    var hasLoadedFile: Bool {
        !previewRows.isEmpty || importedFileName != nil
    }

    func load(transactions: [BankTransactionRow], filename: String, format: BankImportFormat) {
        previewRows = TransactionCategorizationService.previewRows(from: transactions)
        excludedRows = []
        budgetSuggestions = []
        importedFileName = filename
        importedFormat = format
        parseError = nil
        importMessage = nil
        flowFocus = .incoming
        refreshAnalysis()
    }

    func loadFailed(_ message: String) {
        clear(keepMessages: false)
        parseError = message
    }

    func excludeRow(_ row: ImportPreviewRow) {
        previewRows.removeAll { $0.id == row.id }
        excludedRows.append(row)
        excludedRows.sort { $0.transaction.date > $1.transaction.date }
        refreshAnalysis()
    }

    func restoreRow(_ row: ImportPreviewRow) {
        excludedRows.removeAll { $0.id == row.id }
        previewRows.append(row)
        previewRows.sort { $0.transaction.date > $1.transaction.date }
        refreshAnalysis()
    }

    func refreshAnalysis() {
        let result = TransactionAnalysisService.analyze(
            rows: previewRows,
            payeeNotes: payeeNotes,
            amountBasis: amountBasis
        )
        budgetSuggestions = mergeSuggestions(existing: budgetSuggestions, fresh: result.suggestions)
        typicalMonth = result.typicalMonth
    }

    func clear(keepMessages: Bool = false) {
        previewRows = []
        excludedRows = []
        budgetSuggestions = []
        typicalMonth = TypicalMonthSummary()
        importedFileName = nil
        importedFormat = nil
        if !keepMessages {
            parseError = nil
            importMessage = nil
        }
        flowFocus = .incoming
    }

    func rows(matching focus: ImportFlowFocus) -> [ImportPreviewRow] {
        previewRows.filter { focus.includes(budgetType: $0.budgetType) }
    }

    func linkedTransactionIDs(for focus: ImportFlowFocus) -> Set<UUID> {
        Set(
            budgetSuggestions
                .filter { focus.includes(budgetType: $0.budgetType) }
                .flatMap(\.linkedTransactionIDs)
        )
    }

    private func mergeSuggestions(existing: [BudgetSuggestion], fresh: [BudgetSuggestion]) -> [BudgetSuggestion] {
        fresh.map { suggestion in
            var merged = suggestion
            if let prior = existing.first(where: { $0.linkedTransactionIDs == suggestion.linkedTransactionIDs }) {
                merged.isIgnored = prior.isIgnored
                merged.isAccepted = prior.isAccepted
            }
            return merged
        }
    }
}
