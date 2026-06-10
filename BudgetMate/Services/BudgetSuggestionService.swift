import Foundation
import SwiftData

enum BudgetSuggestionService {
    static func createRules(
        from suggestions: [BudgetSuggestion],
        in context: ModelContext
    ) throws -> Int {
        let accepted = suggestions.filter(\.isAccepted)
        guard !accepted.isEmpty else { return 0 }

        for suggestion in accepted {
            let rule = BudgetRule()
            rule.name = suggestion.name
            rule.type = suggestion.budgetType
            rule.category = suggestion.category
            rule.amountMinorUnits = suggestion.amountMinorUnits
            rule.cycle = suggestion.cycle
            rule.startDate = suggestion.startDate
            rule.monthPatternRaw = suggestion.monthPatternRaw
            rule.confidence = suggestion.confidence
            rule.commitment = .known
            rule.assumptionsNotes = combinedAssumptionsNotes(for: suggestion)
            rule.isActive = true
            rule.monthlyEquivalentMinorUnits = BudgetRuleService.calculatedMonthlyEquivalent(for: rule)
            rule.markCreated()
            context.insert(rule)
        }

        try context.save()
        try AppDataService.generateAndRefresh(in: context)
        return accepted.count
    }

    static func excludeLinkedTransactions(
        suggestions: [BudgetSuggestion],
        from previewRows: inout [ImportPreviewRow],
        into excludedRows: inout [ImportPreviewRow]
    ) {
        let linkedIDs = Set(
            suggestions
                .filter(\.isAccepted)
                .flatMap(\.linkedTransactionIDs)
        )
        guard !linkedIDs.isEmpty else { return }

        let toExclude = previewRows.filter { linkedIDs.contains($0.transaction.id) }
        previewRows.removeAll { linkedIDs.contains($0.transaction.id) }
        excludedRows.append(contentsOf: toExclude)
        excludedRows.sort { $0.transaction.date > $1.transaction.date }
    }

    private static func combinedAssumptionsNotes(for suggestion: BudgetSuggestion) -> String {
        var parts = [suggestion.explanation]
        if !suggestion.userNotes.isEmpty {
            parts.append(suggestion.userNotes)
        }
        if !suggestion.bankPayeeSample.isEmpty,
           suggestion.name.caseInsensitiveCompare(PayeeNormalization.displayName(from: suggestion.bankPayeeSample)) != .orderedSame {
            parts.append("Bank payee: \(suggestion.bankPayeeSample)")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
