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

    func removeImportedRow(_ row: ImportPreviewRow) {
        previewRows.removeAll { $0.id == row.id }
        refreshAnalysis()
    }

    func restoreImportedRow(_ row: ImportPreviewRow) {
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
        typicalMonth = TransactionAnalysisService.typicalMonth(
            suggestions: budgetSuggestions,
            previewRows: previewRows
        )
    }

    @discardableResult
    func addManualSuggestion(from rows: [ImportPreviewRow], cycle: BudgetCycleType = .monthly) -> BudgetSuggestion? {
        guard let suggestion = TransactionAnalysisService.makeManualSuggestion(
            from: rows,
            payeeNotes: payeeNotes,
            amountBasis: amountBasis,
            cycle: cycle
        ) else { return nil }

        var manual = suggestion
        manual.isAccepted = true
        budgetSuggestions.append(manual)
        budgetSuggestions.sort { lhs, rhs in
            if lhs.budgetType != rhs.budgetType {
                return lhs.budgetType == .income
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        typicalMonth = TransactionAnalysisService.typicalMonth(
            suggestions: budgetSuggestions,
            previewRows: previewRows
        )
        return manual
    }

    func removeSuggestion(id: UUID) {
        budgetSuggestions.removeAll { $0.id == id }
        typicalMonth = TransactionAnalysisService.typicalMonth(
            suggestions: budgetSuggestions,
            previewRows: previewRows
        )
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
        let manual = existing.filter(\.isManual)
        let previewIDs = Set(previewRows.map(\.id))

        var merged = fresh.map { suggestion in
            var updated = suggestion
            if let prior = existing.first(where: { !$0.isManual && $0.linkedTransactionIDs == suggestion.linkedTransactionIDs }) {
                updated.isIgnored = prior.isIgnored
                updated.isAccepted = prior.isAccepted
            }
            return updated
        }

        let freshLinkedSets = Set(fresh.map(\.linkedTransactionIDs))
        for var manualSuggestion in manual {
            guard manualSuggestion.linkedTransactionIDs.isSubset(of: previewIDs) else { continue }
            guard !freshLinkedSets.contains(manualSuggestion.linkedTransactionIDs) else { continue }
            if let prior = existing.first(where: { $0.id == manualSuggestion.id }) {
                manualSuggestion.isIgnored = prior.isIgnored
                manualSuggestion.isAccepted = prior.isAccepted
            }
            merged.append(manualSuggestion)
        }

        merged.sort { lhs, rhs in
            if lhs.budgetType != rhs.budgetType {
                return lhs.budgetType == .income
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return merged
    }
}
