import Foundation
import SwiftData

enum HolidayCommitError: LocalizedError {
    case noActivities
    case missingPlannedMonth(activityName: String)
    case lockedMonth(monthTitle: String)
    case outsideHorizon(monthTitle: String)

    var errorDescription: String? {
        switch self {
        case .noActivities:
            "Add at least one activity before adding to the monthly plan."
        case .missingPlannedMonth(let name):
            "“\(name)” needs a planned month. Set a default month for the trip or assign one to each activity."
        case .lockedMonth(let title):
            "\(title) is locked. Unlock it in Monthly Plan before adding holiday costs."
        case .outsideHorizon(let title):
            "\(title) is outside your planning horizon. Extend your plan in Settings."
        }
    }
}

enum HolidayService {
    struct Summary {
        let totalMinorUnits: Int
        let countByKind: [HolidayActivityKind: Int]
        let subtotalByKind: [HolidayActivityKind: Int]
    }

    static func fetchAll(in context: ModelContext) throws -> [Holiday] {
        let descriptor = FetchDescriptor<Holiday>(
            sortBy: [
                SortDescriptor(\.displayOrder),
                SortDescriptor(\.name),
            ]
        )
        return try context.fetch(descriptor)
    }

    static func summary(for holiday: Holiday) -> Summary {
        var countByKind: [HolidayActivityKind: Int] = [:]
        var subtotalByKind: [HolidayActivityKind: Int] = [:]
        var total = 0

        for activity in holiday.activities {
            total += activity.amountMinorUnits
            countByKind[activity.kind, default: 0] += 1
            subtotalByKind[activity.kind, default: 0] += activity.amountMinorUnits
        }

        return Summary(
            totalMinorUnits: total,
            countByKind: countByKind,
            subtotalByKind: subtotalByKind
        )
    }

    static func assignDisplayOrderForNewHoliday(_ holiday: Holiday, in context: ModelContext) throws {
        let holidays = try fetchAll(in: context)
        let maxOrder = holidays.map(\.displayOrder).max() ?? -1
        holiday.displayOrder = maxOrder + 1
    }

    static func resolvedPlannedMonth(
        activity: HolidayActivity,
        holiday: Holiday
    ) -> (year: Int, month: Int)? {
        if activity.plannedYear > 0, activity.plannedMonth > 0 {
            return (activity.plannedYear, activity.plannedMonth)
        }
        if holiday.defaultPlannedYear > 0, holiday.defaultPlannedMonth > 0 {
            return (holiday.defaultPlannedYear, holiday.defaultPlannedMonth)
        }
        if let start = holiday.plannedStartDate {
            let components = Calendar.current.dateComponents([.year, .month], from: start)
            if let year = components.year, let month = components.month {
                return (year, month)
            }
        }
        return nil
    }

    static func monthTitle(year: Int, month: Int) -> String {
        BudgetMonth(year: year, month: month).displayTitle
    }

    static func commit(
        holiday: Holiday,
        settings: AppSettings,
        months: [BudgetMonth],
        allTiles: [BudgetTile],
        in context: ModelContext
    ) throws {
        guard !holiday.activities.isEmpty else { throw HolidayCommitError.noActivities }

        let horizonKeys = AppDataService.planningHorizonKeys(for: settings)
        let lockedKeys = Set(months.filter(\.isLocked).map(\.monthKey))

        for activity in holiday.sortedActivities {
            guard let planned = resolvedPlannedMonth(activity: activity, holiday: holiday) else {
                throw HolidayCommitError.missingPlannedMonth(activityName: activity.name)
            }
            let key = "\(planned.year)-\(planned.month)"
            let title = monthTitle(year: planned.year, month: planned.month)
            guard horizonKeys.contains(key) else {
                throw HolidayCommitError.outsideHorizon(monthTitle: title)
            }
            guard !lockedKeys.contains(key) else {
                throw HolidayCommitError.lockedMonth(monthTitle: title)
            }
        }

        for activity in holiday.sortedActivities {
            let planned = resolvedPlannedMonth(activity: activity, holiday: holiday)!
            try syncTile(
                for: activity,
                holiday: holiday,
                year: planned.year,
                month: planned.month,
                allTiles: allTiles,
                in: context
            )
        }

        holiday.status = .committed
        holiday.committedAt = Date()
        holiday.markUpdated()
        try context.save()
        try AppDataService.refreshForecast(in: context)
    }

    static func uncommit(
        holiday: Holiday,
        allTiles: [BudgetTile],
        in context: ModelContext
    ) throws {
        let activityIDs = Set(holiday.activities.map(\.id))
        for tile in allTiles where tile.linkedHolidayActivityId.map(activityIDs.contains) == true {
            context.delete(tile)
        }
        holiday.status = .draft
        holiday.committedAt = nil
        holiday.markUpdated()
        try context.save()
        try AppDataService.refreshForecast(in: context)
    }

    static func syncCommittedHoliday(
        holiday: Holiday,
        settings: AppSettings,
        months: [BudgetMonth],
        allTiles: [BudgetTile],
        in context: ModelContext
    ) throws {
        guard holiday.status == .committed else { return }

        let horizonKeys = AppDataService.planningHorizonKeys(for: settings)
        let lockedKeys = Set(months.filter(\.isLocked).map(\.monthKey))

        for activity in holiday.sortedActivities {
            guard let planned = resolvedPlannedMonth(activity: activity, holiday: holiday) else { continue }
            let key = "\(planned.year)-\(planned.month)"
            guard horizonKeys.contains(key), !lockedKeys.contains(key) else { continue }
            try syncTile(
                for: activity,
                holiday: holiday,
                year: planned.year,
                month: planned.month,
                allTiles: allTiles,
                in: context
            )
        }

        let activityIDs = Set(holiday.activities.map(\.id))
        for tile in allTiles where tile.linkedHolidayActivityId.map(activityIDs.contains) == true {
            if let linkedID = tile.linkedHolidayActivityId,
               !holiday.activities.contains(where: { $0.id == linkedID }) {
                context.delete(tile)
            }
        }

        try context.save()
        try AppDataService.refreshForecast(in: context)
    }

    static func deleteHoliday(
        _ holiday: Holiday,
        allTiles: [BudgetTile],
        in context: ModelContext
    ) throws {
        let activityIDs = Set(holiday.activities.map(\.id))
        for tile in allTiles where tile.linkedHolidayActivityId.map(activityIDs.contains) == true {
            context.delete(tile)
        }
        context.delete(holiday)
        try context.save()
        try AppDataService.refreshForecast(in: context)
    }

    private static func syncTile(
        for activity: HolidayActivity,
        holiday: Holiday,
        year: Int,
        month: Int,
        allTiles: [BudgetTile],
        in context: ModelContext
    ) throws {
        let tileName = tileName(holiday: holiday, activity: activity)
        let existing = allTiles.first { $0.linkedHolidayActivityId == activity.id }

        let tile: BudgetTile
        if let existing {
            tile = existing
        } else {
            tile = BudgetTile(year: year, month: month, name: tileName)
            tile.markCreated()
            tile.source = .holiday
            tile.linkedHolidayActivityId = activity.id
            context.insert(tile)
        }

        tile.year = year
        tile.month = month
        tile.name = tileName
        tile.amountMinorUnits = activity.amountMinorUnits
        tile.type = .expense
        tile.source = .holiday
        tile.status = .active
        tile.linkedAccountId = activity.linkedAccountId
        tile.subCategory = subCategory(for: activity, in: context)
        tile.confidence = activity.estimateSource == .aiSuggested ? .aiSuggested : .estimated
        tile.commitment = .known
        tile.notes = activity.notes
        tile.markUpdated()
    }

    private static func tileName(holiday: Holiday, activity: HolidayActivity) -> String {
        let tripName = holiday.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let activityName = activity.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if tripName.isEmpty { return activityName }
        if activityName.isEmpty { return tripName }
        return "\(tripName) — \(activityName)"
    }

    private static func subCategory(
        for activity: HolidayActivity,
        in context: ModelContext
    ) -> BudgetRuleSubCategory? {
        guard let id = activity.subCategoryId else { return nil }
        let descriptor = FetchDescriptor<BudgetRuleSubCategory>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }
}
