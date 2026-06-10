import Foundation
import SwiftData

enum BudgetRuleService {
    enum DeletionError: Error {
        case notArchived
    }
    struct Summary {
        var incomeMinorUnits: Int = 0
        var expenseMinorUnits: Int = 0
        var savingMinorUnits: Int = 0
        var knownCommitmentsMinorUnits: Int = 0
        var flexibleSpendingMinorUnits: Int = 0
        var activeCount: Int = 0

        var netMinorUnits: Int {
            incomeMinorUnits - expenseMinorUnits - savingMinorUnits
        }
    }

    static func summary(for rules: [BudgetRule]) -> Summary {
        var result = Summary()
        for rule in rules where rule.isActive && !rule.isArchived {
            result.activeCount += 1
            let monthly = monthlyEquivalent(for: rule)
            switch rule.type {
            case .income:
                result.incomeMinorUnits += monthly
            case .expense:
                result.expenseMinorUnits += monthly
                switch rule.commitment {
                case .known: result.knownCommitmentsMinorUnits += monthly
                case .flexible: result.flexibleSpendingMinorUnits += monthly
                }
            case .saving:
                result.savingMinorUnits += monthly
            case .transfer, .adjustment:
                break
            }
        }
        return result
    }

    static func monthlyEquivalent(for rule: BudgetRule) -> Int {
        if rule.monthlyEquivalentMinorUnits > 0 {
            return rule.monthlyEquivalentMinorUnits
        }
        return calculatedMonthlyEquivalent(for: rule)
    }

    static func calculatedMonthlyEquivalent(for rule: BudgetRule) -> Int {
        TransactionAnalysisService.monthlyEquivalentAmount(
            perOccurrence: rule.amountMinorUnits,
            cycle: rule.cycle,
            activeMonthCount: activeMonthCount(for: rule)
        )
    }

    static func activeMonthCount(for rule: BudgetRule) -> Int {
        let months = parseMonthPattern(rule.monthPatternRaw)
        if rule.cycle == .tenMonthly, !months.isEmpty {
            return months.count
        }
        return 10
    }

    static func expiringSoon(from rules: [BudgetRule], withinMonths: Int = 3) -> [BudgetRule] {
        rules
            .filter { isExpiringSoon($0, withinMonths: withinMonths) }
            .sorted { ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture) }
    }

    static func isExpiringSoon(_ rule: BudgetRule, withinMonths: Int = 3) -> Bool {
        guard rule.isActive, !rule.isArchived, let endDate = rule.endDate else { return false }
        guard let cutoff = Calendar.current.date(byAdding: .month, value: withinMonths, to: .now) else {
            return false
        }
        return endDate <= cutoff
    }

    static func parseMonthPattern(_ raw: String) -> Set<Int> {
        Set(
            raw
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { (1...12).contains($0) }
        )
    }

    static func formatMonthPattern(_ months: Set<Int>) -> String {
        months.sorted().map(String.init).joined(separator: ",")
    }

    static func formatMonthPatternDisplay(_ raw: String) -> String {
        let months = parseMonthPattern(raw).sorted()
        guard !months.isEmpty else { return "—" }
        let symbols = Calendar.current.shortMonthSymbols
        return months.map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    static func recurringTiles(for rule: BudgetRule, in tiles: [BudgetTile]) -> [BudgetTile] {
        tiles.filter { $0.linkedRuleId == rule.id && $0.source == .recurring }
    }

    static func deletePermanently(
        rule: BudgetRule,
        tiles: [BudgetTile],
        in context: ModelContext
    ) throws {
        guard rule.isArchived else { throw DeletionError.notArchived }

        for tile in recurringTiles(for: rule, in: tiles) {
            context.delete(tile)
        }
        context.delete(rule)
        try context.save()
    }
}
