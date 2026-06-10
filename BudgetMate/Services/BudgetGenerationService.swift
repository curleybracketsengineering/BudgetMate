import Foundation
import SwiftData

enum BudgetGenerationService {
    static func generateTiles(
        rules: [BudgetRule],
        settings: AppSettings,
        months: [BudgetMonth],
        existingTiles: [BudgetTile]
    ) -> [BudgetTile] {
        var newTiles: [BudgetTile] = []
        let lockedKeys = Set(months.filter(\.isLocked).map(\.monthKey))
        let recurringTiles = existingTiles.filter { $0.source == .recurring }

        let sequence = PlanningCalendar.monthSequence(
            startYear: settings.planningStartYear,
            startMonth: settings.planningStartMonth,
            count: settings.horizonMonths
        )

        for rule in rules where rule.isActive && !rule.isArchived {
            for slot in sequence {
                let key = "\(slot.year)-\(slot.month)"
                if lockedKeys.contains(key) { continue }
                if !shouldGenerate(rule: rule, year: slot.year, month: slot.month) { continue }

                let alreadyExists = recurringTiles.contains {
                    $0.linkedRuleId == rule.id && $0.year == slot.year && $0.month == slot.month && $0.isActive
                }
                if alreadyExists { continue }

                let tile = BudgetTile(year: slot.year, month: slot.month, name: rule.name)
                tile.amountMinorUnits = rule.amountMinorUnits
                tile.type = rule.type
                tile.category = rule.category
                tile.source = .recurring
                tile.status = .active
                tile.confidence = rule.confidence
                tile.commitment = rule.commitment
                tile.linkedRuleId = rule.id
                tile.linkedAccountId = rule.linkedAccountId
                tile.transferToAccountId = rule.transferToAccountId
                tile.notes = rule.assumptionsNotes
                tile.markCreated()
                newTiles.append(tile)
            }
        }

        return newTiles
    }

    static func shouldGenerate(rule: BudgetRule, year: Int, month: Int) -> Bool {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.year, .month, .day], from: rule.startDate)
        guard let startYear = startComponents.year, let startMonth = startComponents.month else { return false }

        let comparison = PlanningCalendar.compare(year1: year, month1: month, to: startYear, month2: startMonth)
        if comparison == .orderedAscending { return false }

        if let endDate = rule.endDate {
            let endComponents = calendar.dateComponents([.year, .month], from: endDate)
            guard let endYear = endComponents.year, let endMonth = endComponents.month else { return false }
            let endComparison = PlanningCalendar.compare(year1: year, month1: month, to: endYear, month2: endMonth)
            if endComparison == .orderedDescending { return false }
        }

        switch rule.cycle {
        case .monthly:
            return true
        case .yearly:
            return month == startMonth
        case .quarterly:
            let monthsFromStart = monthsFrom(startYear: startYear, startMonth: startMonth, toYear: year, toMonth: month)
            return monthsFromStart >= 0 && monthsFromStart % 3 == 0
        case .weekly:
            return monthContainsIntervalPayment(rule: rule, year: year, month: month, intervalDays: 7)
        case .everyFourWeeks:
            return monthContainsIntervalPayment(rule: rule, year: year, month: month, intervalDays: 28)
        case .tenMonthly:
            let activeMonths = parseMonthPattern(rule.monthPatternRaw)
            guard !activeMonths.isEmpty else { return false }
            return activeMonths.contains(month)
        case .oneOff:
            return year == startYear && month == startMonth
        case .custom:
            return true
        }
    }

    private static func parseMonthPattern(_ raw: String) -> Set<Int> {
        Set(
            raw
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { (1...12).contains($0) }
        )
    }

    private static func monthContainsIntervalPayment(
        rule: BudgetRule,
        year: Int,
        month: Int,
        intervalDays: Int
    ) -> Bool {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let monthStart = Calendar.current.date(from: components),
              let monthRange = Calendar.current.range(of: .day, in: .month, for: monthStart),
              let monthEnd = Calendar.current.date(byAdding: .day, value: monthRange.count - 1, to: monthStart) else {
            return false
        }

        var paymentDate = rule.startDate
        while paymentDate < monthStart {
            guard let next = Calendar.current.date(byAdding: .day, value: intervalDays, to: paymentDate) else {
                return false
            }
            paymentDate = next
        }

        if paymentDate <= monthEnd {
            if let endDate = rule.endDate, paymentDate > endDate { return false }
            return paymentDate >= rule.startDate
        }

        return false
    }

    private static func monthsFrom(startYear: Int, startMonth: Int, toYear: Int, toMonth: Int) -> Int {
        (toYear - startYear) * 12 + (toMonth - startMonth)
    }
}
