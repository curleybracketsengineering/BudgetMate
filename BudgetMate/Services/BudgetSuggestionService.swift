import Foundation
import SwiftData

enum BudgetSuggestionService {
    struct CreatedRuleResult {
        let ruleID: UUID
        let name: String
    }

    static func createRule(
        from row: ImportPreviewRow,
        payeeNotes: [String: PayeeNote],
        in context: ModelContext
    ) throws -> CreatedRuleResult {
        let transaction = row.transaction
        let payeeSample = transaction.payee
        let name = PayeeNoteService.resolvedTitle(for: payeeSample, in: payeeNotes)

        var (cycle, activeMonths, explanation) = TransactionAnalysisService.inferredCycle(for: row)
        if cycle == .oneOff {
            cycle = .monthly
            explanation = "Monthly recurring item created from a single bank transaction. Confirm cycle in Budget Rules."
        }

        let rule = BudgetRule()
        rule.name = name
        rule.type = row.budgetType
        BudgetRuleSubCategoryService.assignSubCategory(to: rule, title: row.suggestedSubCategoryTitle, in: context)
        rule.amountMinorUnits = transaction.amountMinorUnits
        rule.cycle = cycle
        rule.startDate = transaction.date
        rule.monthPatternRaw = activeMonths.map(String.init).joined(separator: ",")
        rule.confidence = .estimated
        rule.commitment = commitment(for: row)
        rule.assumptionsNotes = assumptionsNotes(
            explanation: explanation,
            payeeSample: payeeSample,
            name: name,
            payeeNotes: payeeNotes
        )
        rule.isActive = true
        rule.monthlyEquivalentMinorUnits = rule.cycle.countsTowardMonthlySummary
            ? BudgetRuleService.calculatedMonthlyEquivalent(for: rule)
            : 0
        try BudgetRuleService.assignDisplayOrderForNewRule(rule, in: context)
        rule.markCreated()
        context.insert(rule)

        try context.save()
        try AppDataService.generateAndRefresh(in: context)
        return CreatedRuleResult(ruleID: rule.id, name: name)
    }

    static func deleteRule(id: UUID, in context: ModelContext) throws {
        let rules = try context.fetch(FetchDescriptor<BudgetRule>())
        guard let rule = rules.first(where: { $0.id == id }) else { return }

        let tiles = try context.fetch(FetchDescriptor<BudgetTile>())
        for tile in tiles where tile.linkedRuleId == id {
            context.delete(tile)
        }
        context.delete(rule)
        try context.save()
        try AppDataService.refreshForecast(in: context)
    }

    static func createRules(
        from rows: [ImportPreviewRow],
        payeeNotes: [String: PayeeNote],
        in context: ModelContext
    ) throws -> [CreatedRuleResult] {
        let eligible = rows.filter {
            $0.budgetType == .income || $0.budgetType == .expense || $0.budgetType == .saving
        }
        let byPayee = Dictionary(grouping: eligible) { PayeeNormalization.matchKey($0.transaction.payee) }
        var results: [CreatedRuleResult] = []
        for (_, payeeRows) in byPayee {
            guard let row = payeeRows.max(by: { $0.transaction.date < $1.transaction.date }) else { continue }
            results.append(try createRule(from: row, payeeNotes: payeeNotes, in: context))
        }
        return results
    }

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
            BudgetRuleSubCategoryService.assignSubCategory(
                to: rule,
                title: suggestion.suggestedSubCategoryTitle,
                in: context
            )
            rule.amountMinorUnits = suggestion.amountMinorUnits
            rule.cycle = suggestion.cycle
            rule.startDate = suggestion.startDate
            rule.monthPatternRaw = suggestion.monthPatternRaw
            rule.confidence = suggestion.confidence
            rule.commitment = .known
            rule.assumptionsNotes = combinedAssumptionsNotes(for: suggestion)
            rule.isActive = true
            rule.monthlyEquivalentMinorUnits = rule.cycle.countsTowardMonthlySummary
                ? BudgetRuleService.calculatedMonthlyEquivalent(for: rule)
                : 0
            try BudgetRuleService.assignDisplayOrderForNewRule(rule, in: context)
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

    private static func commitment(for row: ImportPreviewRow) -> CommitmentType {
        switch row.budgetType {
        case .expense where row.suggestedSubCategoryTitle == "Spending":
            return .flexible
        default:
            return .known
        }
    }

    private static func assumptionsNotes(
        explanation: String,
        payeeSample: String,
        name: String,
        payeeNotes: [String: PayeeNote]
    ) -> String {
        var parts = [explanation]
        if let note = payeeNotes[PayeeNormalization.matchKey(payeeSample)] {
            let userNotes = note.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !userNotes.isEmpty {
                parts.append(userNotes)
            }
        }
        if !payeeSample.isEmpty,
           name.caseInsensitiveCompare(PayeeNormalization.displayName(from: payeeSample)) != .orderedSame {
            parts.append("Bank payee: \(payeeSample)")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
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
