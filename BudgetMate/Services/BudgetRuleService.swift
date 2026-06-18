import Foundation
import SwiftData

enum BudgetRuleService {
    enum OrderGroup {
        case incoming
        case outgoing
        case other

        static func forType(_ type: BudgetType) -> OrderGroup {
            switch type {
            case .income: .incoming
            case .expense, .saving: .outgoing
            case .transfer, .adjustment: .other
            }
        }
    }

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
        switch rule.cycle {
        case .tenMonthly:
            return months.isEmpty ? 10 : months.count
        case .custom:
            return months.count
        default:
            return 10
        }
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

    struct PlanningPeriod {
        let startYear: Int
        let startMonth: Int
        let endYear: Int
        let endMonth: Int

        var label: String {
            "\(Self.formatYearMonth(startYear, startMonth)) – \(Self.formatYearMonth(endYear, endMonth))"
        }

        static func from(settings: AppSettings) -> PlanningPeriod? {
            let sequence = PlanningCalendar.monthSequence(
                startYear: settings.planningStartYear,
                startMonth: settings.planningStartMonth,
                count: settings.horizonMonths
            )
            guard let first = sequence.first, let last = sequence.last else { return nil }
            return PlanningPeriod(
                startYear: first.year,
                startMonth: first.month,
                endYear: last.year,
                endMonth: last.month
            )
        }

        static func formatYearMonth(_ year: Int, _ month: Int) -> String {
            PlanningCalendar.firstDayOfMonth(year: year, month: month)
                .formatted(.dateTime.month(.abbreviated).year())
        }
    }

    enum PlanningOverlap {
        case endsBeforePlan(endLabel: String, planLabel: String)
        case startsAfterPlan(startLabel: String, planLabel: String)
    }

    static func planningOverlap(for rule: BudgetRule, settings: AppSettings) -> PlanningOverlap? {
        guard let period = PlanningPeriod.from(settings: settings) else { return nil }
        let ruleStart = yearMonth(from: rule.startDate)

        if PlanningCalendar.compare(
            year1: ruleStart.year,
            month1: ruleStart.month,
            to: period.endYear,
            month2: period.endMonth
        ) == .orderedDescending {
            return .startsAfterPlan(
                startLabel: PlanningPeriod.formatYearMonth(ruleStart.year, ruleStart.month),
                planLabel: period.label
            )
        }

        if let endDate = rule.endDate {
            let ruleEnd = yearMonth(from: endDate)
            if PlanningCalendar.compare(
                year1: ruleEnd.year,
                month1: ruleEnd.month,
                to: period.startYear,
                month2: period.startMonth
            ) == .orderedAscending {
                return .endsBeforePlan(
                    endLabel: PlanningPeriod.formatYearMonth(ruleEnd.year, ruleEnd.month),
                    planLabel: period.label
                )
            }
        }

        return nil
    }

    static func generateTilesEmptyMessage(for rules: [BudgetRule], settings: AppSettings) -> String {
        let active = rules.filter { $0.isActive && !$0.isArchived }
        if active.isEmpty {
            return "No active rules to generate from. Add a rule with an amount first."
        }

        guard let period = PlanningPeriod.from(settings: settings) else {
            return "Your planning horizon has no months. Check Settings."
        }

        let endedBeforePlan = active.filter {
            if case .endsBeforePlan = planningOverlap(for: $0, settings: settings) { return true }
            return false
        }
        if !endedBeforePlan.isEmpty {
            return """
            \(endedBeforePlan.count) active rule\(endedBeforePlan.count == 1 ? "" : "s") ha\(endedBeforePlan.count == 1 ? "s" : "ve") an end date before your planning period (\(period.label)). Remove or extend the end date, then try again.
            """
        }

        let startsAfterPlan = active.filter {
            if case .startsAfterPlan = planningOverlap(for: $0, settings: settings) { return true }
            return false
        }
        if !startsAfterPlan.isEmpty {
            return """
            \(startsAfterPlan.count) active rule\(startsAfterPlan.count == 1 ? "" : "s") start\(startsAfterPlan.count == 1 ? "s" : "") after your planning period (\(period.label)). Tiles are only created from each rule's start date onward — adjust the rule start date or change Settings → Planning start.
            """
        }

        if active.allSatisfy({ $0.amountMinorUnits == 0 }) {
            return "Active rules have no amounts set. Edit rules and add amounts, then try again."
        }

        return "Tiles for all active rules already exist in your plan."
    }

    private static func yearMonth(from date: Date) -> (year: Int, month: Int) {
        let calendar = Calendar.current
        return (
            calendar.component(.year, from: date),
            calendar.component(.month, from: date)
        )
    }

    static func recurringTiles(for rule: BudgetRule, in tiles: [BudgetTile]) -> [BudgetTile] {
        tiles.filter { $0.linkedRuleId == rule.id && $0.source == .recurring }
    }

    static func sorted(_ rules: [BudgetRule]) -> [BudgetRule] {
        rules.sorted { lhs, rhs in
            if lhs.displayOrder != rhs.displayOrder {
                return lhs.displayOrder < rhs.displayOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func rules(in group: OrderGroup, from rules: [BudgetRule]) -> [BudgetRule] {
        sorted(rules.filter { OrderGroup.forType($0.type) == group })
    }

    static func assignDisplayOrderForNewRule(_ rule: BudgetRule, in context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<BudgetRule>())
        let group = OrderGroup.forType(rule.type)
        let inGroup = all.filter { OrderGroup.forType($0.type) == group && $0.id != rule.id }
        rule.displayOrder = (inGroup.map(\.displayOrder).max() ?? -1) + 1
    }

    static func persistDisplayOrder(_ orderedRules: [BudgetRule], in context: ModelContext) throws {
        for (index, rule) in orderedRules.enumerated() {
            rule.displayOrder = index
            rule.markUpdated()
        }
        try context.save()
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
