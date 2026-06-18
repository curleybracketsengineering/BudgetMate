import Foundation
import SwiftData

enum BudgetGenerationService {
    struct SyncResult {
        var removed: Int = 0
        var added: Int = 0
        var updated: Int = 0
    }

    struct TileSlot: Hashable {
        let year: Int
        let month: Int
        let occurrenceIndex: Int
    }

    /// Aligns recurring tiles for one rule with its current schedule and fields.
    /// The payment cycle is anchored at `rule.startDate`; tiles are only created within the planning horizon.
    static func syncTiles(
        for rule: BudgetRule,
        settings: AppSettings,
        months: [BudgetMonth],
        allTiles: [BudgetTile],
        in context: ModelContext
    ) -> SyncResult {
        var result = SyncResult()
        let lockedKeys = Set(months.filter(\.isLocked).map(\.monthKey))
        let planningSequence = planningMonthSequence(settings: settings)
        let planningKeys = Set(planningSequence.map { monthKey(year: $0.year, month: $0.month) })
        let shouldSchedule = rule.isActive && !rule.isArchived
        let ruleTiles = allTiles.filter { $0.linkedRuleId == rule.id && $0.source == .recurring }

        if !shouldSchedule {
            for tile in ruleTiles where !lockedKeys.contains(tile.monthKey) {
                context.delete(tile)
                result.removed += 1
            }
            return result
        }

        var expectedByMonth: [String: [TileSlot]] = [:]
        for slot in planningSequence {
            let key = monthKey(year: slot.year, month: slot.month)
            if lockedKeys.contains(key) { continue }
            let occurrences = paymentOccurrences(for: rule, year: slot.year, month: slot.month)
            for index in occurrences.indices {
                let tileSlot = TileSlot(year: slot.year, month: slot.month, occurrenceIndex: index)
                expectedByMonth[key, default: []].append(tileSlot)
            }
        }

        for tile in ruleTiles {
            if lockedKeys.contains(tile.monthKey) { continue }

            if !planningKeys.contains(tile.monthKey) {
                context.delete(tile)
                result.removed += 1
                continue
            }

            if expectedByMonth[tile.monthKey] == nil {
                context.delete(tile)
                result.removed += 1
            }
        }

        for monthSlots in expectedByMonth.values {
            guard let first = monthSlots.first else { continue }
            let existingInMonth = ruleTiles
                .filter { $0.year == first.year && $0.month == first.month && !lockedKeys.contains($0.monthKey) }
                .sorted {
                    if $0.recurringOccurrenceIndex != $1.recurringOccurrenceIndex {
                        return $0.recurringOccurrenceIndex < $1.recurringOccurrenceIndex
                    }
                    return $0.createdAt < $1.createdAt
                }

            for (index, slot) in monthSlots.enumerated() {
                let tile: BudgetTile?
                if index < existingInMonth.count {
                    tile = existingInMonth[index]
                } else {
                    tile = nil
                }

                if let tile {
                    tile.recurringOccurrenceIndex = slot.occurrenceIndex
                    if updateTile(tile, from: rule) {
                        result.updated += 1
                    }
                } else {
                    let newTile = makeRecurringTile(
                        from: rule,
                        year: slot.year,
                        month: slot.month,
                        occurrenceIndex: slot.occurrenceIndex
                    )
                    context.insert(newTile)
                    result.added += 1
                }
            }

            if existingInMonth.count > monthSlots.count {
                for extra in existingInMonth.dropFirst(monthSlots.count) {
                    context.delete(extra)
                    result.removed += 1
                }
            }
        }

        return result
    }

    /// Calendar months in the planning horizon that contain at least one payment for this rule.
    static func scheduledMonthLabels(for rule: BudgetRule, settings: AppSettings) -> [String] {
        planningMonthSequence(settings: settings).compactMap { slot in
            let count = paymentOccurrences(for: rule, year: slot.year, month: slot.month).count
            guard count > 0 else { return nil }
            let label = BudgetRuleService.PlanningPeriod.formatYearMonth(slot.year, slot.month)
            if count > 1 {
                return "\(label) (×\(count))"
            }
            return label
        }
    }

    static func shouldGenerate(rule: BudgetRule, year: Int, month: Int, settings: AppSettings) -> Bool {
        guard isWithinPlanningHorizon(year: year, month: month, settings: settings) else { return false }
        return !paymentOccurrences(for: rule, year: year, month: month).isEmpty
    }

    /// Payment dates in a calendar month. The cycle is anchored at `rule.startDate` (which may be before the planning horizon).
    static func paymentOccurrences(for rule: BudgetRule, year: Int, month: Int) -> [Date] {
        switch rule.cycle {
        case .weekly:
            return paymentDatesWithInterval(rule: rule, year: year, month: month, intervalDays: 7)
        case .everyFourWeeks:
            return paymentDatesWithInterval(rule: rule, year: year, month: month, intervalDays: 28)
        case .monthly:
            guard isActiveCalendarMonth(rule: rule, year: year, month: month) else { return [] }
            return [anchorDate(inYear: year, month: month, from: rule.startDate)]
        case .yearly:
            guard isActiveCalendarMonth(rule: rule, year: year, month: month) else { return [] }
            let startComponents = Calendar.current.dateComponents([.year, .month], from: rule.startDate)
            guard startComponents.month == month else { return [] }
            guard year >= (startComponents.year ?? year) else { return [] }
            return [anchorDate(inYear: year, month: month, from: rule.startDate)]
        case .quarterly:
            guard isActiveCalendarMonth(rule: rule, year: year, month: month) else { return [] }
            let startComponents = Calendar.current.dateComponents([.year, .month], from: rule.startDate)
            guard let startYear = startComponents.year, let startMonth = startComponents.month else { return [] }
            let monthsFromStart = monthsFrom(startYear: startYear, startMonth: startMonth, toYear: year, toMonth: month)
            guard monthsFromStart >= 0, monthsFromStart % 3 == 0 else { return [] }
            return [anchorDate(inYear: year, month: month, from: rule.startDate)]
        case .twiceYearly:
            guard isActiveCalendarMonth(rule: rule, year: year, month: month) else { return [] }
            let startComponents = Calendar.current.dateComponents([.year, .month], from: rule.startDate)
            guard let startYear = startComponents.year, let startMonth = startComponents.month else { return [] }
            let monthsFromStart = monthsFrom(startYear: startYear, startMonth: startMonth, toYear: year, toMonth: month)
            guard monthsFromStart >= 0, monthsFromStart % 6 == 0 else { return [] }
            return [anchorDate(inYear: year, month: month, from: rule.startDate)]
        case .tenMonthly, .custom:
            guard isActiveCalendarMonth(rule: rule, year: year, month: month) else { return [] }
            let activeMonths = parseMonthPattern(rule.monthPatternRaw)
            guard activeMonths.contains(month) else { return [] }
            return [anchorDate(inYear: year, month: month, from: rule.startDate)]
        case .oneOff:
            let startComponents = Calendar.current.dateComponents([.year, .month], from: rule.startDate)
            guard startComponents.year == year, startComponents.month == month else { return [] }
            return [rule.startDate]
        }
    }

    // MARK: - Private

    private static func planningMonthSequence(settings: AppSettings) -> [(year: Int, month: Int)] {
        PlanningCalendar.monthSequence(
            startYear: settings.planningStartYear,
            startMonth: settings.planningStartMonth,
            count: settings.horizonMonths
        )
    }

    private static func isWithinPlanningHorizon(year: Int, month: Int, settings: AppSettings) -> Bool {
        planningMonthSequence(settings: settings).contains { $0.year == year && $0.month == month }
    }

    private static func monthKey(year: Int, month: Int) -> String {
        "\(year)-\(month)"
    }

    private static func isActiveCalendarMonth(rule: BudgetRule, year: Int, month: Int) -> Bool {
        let startComponents = Calendar.current.dateComponents([.year, .month], from: rule.startDate)
        guard let startYear = startComponents.year, let startMonth = startComponents.month else { return false }

        if PlanningCalendar.compare(year1: year, month1: month, to: startYear, month2: startMonth) == .orderedAscending {
            return false
        }

        if let endDate = rule.endDate {
            let endComponents = Calendar.current.dateComponents([.year, .month], from: endDate)
            guard let endYear = endComponents.year, let endMonth = endComponents.month else { return false }
            if PlanningCalendar.compare(year1: year, month1: month, to: endYear, month2: endMonth) == .orderedDescending {
                return false
            }
        }

        return true
    }

    private static func paymentDatesWithInterval(
        rule: BudgetRule,
        year: Int,
        month: Int,
        intervalDays: Int
    ) -> [Date] {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthRange = calendar.range(of: .day, in: .month, for: monthStart),
              let monthEnd = calendar.date(byAdding: .day, value: monthRange.count - 1, to: monthStart) else {
            return []
        }

        var paymentDate = rule.startDate
        while paymentDate < monthStart {
            guard let next = calendar.date(byAdding: .day, value: intervalDays, to: paymentDate) else {
                return []
            }
            paymentDate = next
        }

        var dates: [Date] = []
        while paymentDate <= monthEnd {
            if paymentDate >= rule.startDate {
                if let endDate = rule.endDate, paymentDate > endDate { break }
                dates.append(paymentDate)
            }
            guard let next = calendar.date(byAdding: .day, value: intervalDays, to: paymentDate) else {
                break
            }
            paymentDate = next
        }

        return dates
    }

    private static func anchorDate(inYear year: Int, month: Int, from startDate: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: startDate)
        guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return startDate
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = min(day, monthRange.count)
        return calendar.date(from: components) ?? startDate
    }

    private static func parseMonthPattern(_ raw: String) -> Set<Int> {
        Set(
            raw
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { (1...12).contains($0) }
        )
    }

    private static func monthsFrom(startYear: Int, startMonth: Int, toYear: Int, toMonth: Int) -> Int {
        (toYear - startYear) * 12 + (toMonth - startMonth)
    }

    private static func makeRecurringTile(
        from rule: BudgetRule,
        year: Int,
        month: Int,
        occurrenceIndex: Int
    ) -> BudgetTile {
        let tile = BudgetTile(year: year, month: month, name: rule.name)
        applyRuleProperties(to: tile, from: rule)
        tile.source = .recurring
        tile.status = .active
        tile.linkedRuleId = rule.id
        tile.recurringOccurrenceIndex = occurrenceIndex
        tile.markCreated()
        return tile
    }

    @discardableResult
    private static func updateTile(_ tile: BudgetTile, from rule: BudgetRule) -> Bool {
        let changed = applyRuleProperties(to: tile, from: rule)
        if tile.status != .active {
            tile.status = .active
            return true
        }
        return changed
    }

    @discardableResult
    private static func applyRuleProperties(to tile: BudgetTile, from rule: BudgetRule) -> Bool {
        var changed = false

        if tile.name != rule.name {
            tile.name = rule.name
            changed = true
        }
        if tile.amountMinorUnits != rule.amountMinorUnits {
            tile.amountMinorUnits = rule.amountMinorUnits
            changed = true
        }
        if tile.type != rule.type {
            tile.type = rule.type
            changed = true
        }
        if tile.category != rule.category {
            tile.category = rule.category
            changed = true
        }
        if tile.confidence != rule.confidence {
            tile.confidence = rule.confidence
            changed = true
        }
        if tile.commitment != rule.commitment {
            tile.commitment = rule.commitment
            changed = true
        }
        if tile.linkedAccountId != rule.linkedAccountId {
            tile.linkedAccountId = rule.linkedAccountId
            changed = true
        }
        let transferId = rule.type == .transfer ? rule.transferToAccountId : nil
        if tile.transferToAccountId != transferId {
            tile.transferToAccountId = transferId
            changed = true
        }
        if tile.notes != rule.assumptionsNotes {
            tile.notes = rule.assumptionsNotes
            changed = true
        }

        if changed {
            tile.markUpdated()
        }
        return changed
    }
}
