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

    static func resolvedStartDate(activity: HolidayActivity, holiday: Holiday) -> Date? {
        if usesExplicitActivityDates(activity),
           let start = activity.plannedStartDate {
            return Calendar.current.startOfDay(for: start)
        }
        if let range = sequentialDateRange(activity: activity, holiday: holiday) {
            return range.start
        }
        if let month = resolvedPlannedMonth(activity: activity, holiday: holiday) {
            return PlanningCalendar.firstDayOfMonth(year: month.year, month: month.month)
        }
        return nil
    }

    static func resolvedEndDate(activity: HolidayActivity, holiday: Holiday) -> Date? {
        let calendar = Calendar.current
        if usesExplicitActivityDates(activity) {
            if let end = activity.plannedEndDate {
                return calendar.startOfDay(for: end)
            }
            if let start = activity.plannedStartDate {
                let startDay = calendar.startOfDay(for: start)
                if activity.kind == .hotels, activity.nights > 1 {
                    return calendar.date(byAdding: .day, value: activity.nights - 1, to: startDay) ?? startDay
                }
                return startDay
            }
        }
        if let range = sequentialDateRange(activity: activity, holiday: holiday) {
            return range.end
        }
        if let start = resolvedStartDate(activity: activity, holiday: holiday) {
            return start
        }
        return nil
    }

    static func activitySpanDays(activity: HolidayActivity, holiday: Holiday) -> Int {
        if activity.kind == .hotels, activity.nights > 0 {
            return activity.nights
        }
        guard let start = resolvedStartDate(activity: activity, holiday: holiday) else { return 1 }
        let end = resolvedEndDate(activity: activity, holiday: holiday) ?? start
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
    }

    static func isActivityStartTripDay(
        activity: HolidayActivity,
        holiday: Holiday,
        tripDay: Int
    ) -> Bool {
        guard let tripStart = holiday.plannedStartDate,
              let start = resolvedStartDate(activity: activity, holiday: holiday) else {
            return false
        }
        return HolidayItineraryService.tripDay(for: start, tripStart: tripStart) == tripDay
    }

    static func hotelStayNightLabel(
        activity: HolidayActivity,
        holiday: Holiday,
        tripDay: Int
    ) -> String? {
        guard activity.kind == .hotels,
              let tripStart = holiday.plannedStartDate,
              let start = resolvedStartDate(activity: activity, holiday: holiday) else {
            return nil
        }

        let startTripDay = HolidayItineraryService.tripDay(for: start, tripStart: tripStart)
        let totalNights = activitySpanDays(activity: activity, holiday: holiday)
        let nightNumber = tripDay - startTripDay + 1
        guard nightNumber >= 1, nightNumber <= totalNights else { return nil }

        if nightNumber == 1 {
            return totalNights == 1 ? "1 night" : "\(totalNights) nights"
        }
        return "Night \(nightNumber) of \(totalNights)"
    }

    struct ActivityCompactDateParts {
        let topLine: String
        let bottomLine: String
    }

    private static let compactDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d")
        formatter.timeStyle = .none
        return formatter
    }()

    private static let compactMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        formatter.timeStyle = .none
        return formatter
    }()

    static func activityCompactDateParts(
        activity: HolidayActivity,
        holiday: Holiday
    ) -> ActivityCompactDateParts? {
        guard let start = resolvedStartDate(activity: activity, holiday: holiday) else { return nil }
        let end = resolvedEndDate(activity: activity, holiday: holiday) ?? start
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)

        let topLine: String
        if endDay > startDay {
            topLine = "\(compactDayFormatter.string(from: startDay))–\(compactDayFormatter.string(from: endDay))"
        } else {
            topLine = compactDayFormatter.string(from: startDay)
        }

        return ActivityCompactDateParts(
            topLine: topLine,
            bottomLine: compactMonthFormatter.string(from: startDay)
        )
    }

    static func activityCompactDateLabel(activity: HolidayActivity, holiday: Holiday) -> String? {
        guard let parts = activityCompactDateParts(activity: activity, holiday: holiday) else { return nil }
        return "\(parts.topLine) \(parts.bottomLine)"
    }

    private static func usesExplicitActivityDates(_ activity: HolidayActivity) -> Bool {
        activity.plannedStartDate != nil && activity.estimateSource == .manual
    }

    private static func sequentialDateRange(
        activity: HolidayActivity,
        holiday: Holiday
    ) -> (start: Date, end: Date)? {
        guard let tripStart = holiday.plannedStartDate else { return nil }

        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: tripStart)

        for candidate in holiday.sortedActivities {
            let stayNights = candidate.nights
            let start = cursor
            let end: Date
            let nextCursor: Date

            if stayNights > 0 {
                end = calendar.date(byAdding: .day, value: stayNights - 1, to: cursor) ?? cursor
                nextCursor = calendar.date(byAdding: .day, value: stayNights, to: cursor) ?? cursor
            } else {
                end = cursor
                nextCursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            }

            if candidate.id == activity.id {
                return (start, end)
            }
            cursor = nextCursor
        }

        return nil
    }

    static func activityDateRangeLabel(activity: HolidayActivity, holiday: Holiday) -> String? {
        guard let start = resolvedStartDate(activity: activity, holiday: holiday) else { return nil }
        let end = resolvedEndDate(activity: activity, holiday: holiday) ?? start
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        if endDay > startDay {
            let sameYear = calendar.component(.year, from: startDay) == calendar.component(.year, from: endDay)
            if sameYear {
                let startFormatter = DateFormatter()
                startFormatter.setLocalizedDateFormatFromTemplate("d MMM")
                startFormatter.timeStyle = .none
                return "\(startFormatter.string(from: startDay)) – \(formatter.string(from: endDay))"
            }
            return "\(formatter.string(from: startDay)) – \(formatter.string(from: endDay))"
        }
        return formatter.string(from: startDay)
    }

    static func activities(on day: Date, holiday: Holiday) -> [HolidayActivity] {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: day)
        let dateMaps = resolvedDateMaps(for: holiday)
        let startDates = dateMaps.starts
        let endDates = dateMaps.ends
        return holiday.activities
            .sorted { compareChronologically($0, $1, startDates: startDates) }
            .filter { activity in
                guard let start = startDates[activity.id] else { return false }
                let end = endDates[activity.id] ?? start
                let startDay = calendar.startOfDay(for: start)
                let endDay = calendar.startOfDay(for: end)
                return targetDay >= startDay && targetDay <= endDay
            }
    }

    static func activitiesStarting(on day: Date, holiday: Holiday) -> [HolidayActivity] {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: day)
        let startDates = resolvedDateMaps(for: holiday).starts
        return holiday.activities
            .sorted { compareChronologically($0, $1, startDates: startDates) }
            .filter { activity in
                guard let start = startDates[activity.id] else { return false }
                return calendar.isDate(start, inSameDayAs: targetDay)
            }
    }

    struct TripDaySection: Identifiable {
        let day: Int
        let date: Date
        var activities: [HolidayActivity]
        var activitiesStartingOnDay: [HolidayActivity]
        var id: Int { day }
    }

    static func tripDaySections(
        for holiday: Holiday,
        includingActivityIDs: Set<UUID>? = nil
    ) -> ([TripDaySection], unscheduled: [HolidayActivity])? {
        guard let tripStart = holiday.plannedStartDate,
              let tripDayCount = HolidayItineraryService.tripDayCount(for: holiday) else {
            return nil
        }

        let dateMaps = resolvedDateMaps(for: holiday)
        let startDates = dateMaps.starts
        let endDates = dateMaps.ends
        let sorted = holiday.activities.sorted { lhs, rhs in
            compareChronologically(lhs, rhs, startDates: startDates)
        }
        let filtered = sorted.filter { activity in
            guard let includingActivityIDs else { return true }
            return includingActivityIDs.contains(activity.id)
        }

        var unscheduled: [HolidayActivity] = []
        var lastActivityDay = 1
        var activitiesByTripDay: [Int: [HolidayActivity]] = [:]
        var startingActivitiesByTripDay: [Int: [HolidayActivity]] = [:]

        for activity in filtered {
            guard let start = startDates[activity.id] else {
                unscheduled.append(activity)
                continue
            }
            let end = endDates[activity.id] ?? start
            let startTripDay = HolidayItineraryService.tripDay(for: start, tripStart: tripStart)
            let endTripDay = HolidayItineraryService.tripDay(for: end, tripStart: tripStart)
            lastActivityDay = max(lastActivityDay, endTripDay)

            startingActivitiesByTripDay[startTripDay, default: []].append(activity)
            if startTripDay <= endTripDay {
                for day in startTripDay...endTripDay {
                    activitiesByTripDay[day, default: []].append(activity)
                }
            }
        }

        let visibleDayCount = min(max(lastActivityDay, 1), tripDayCount)

        let sections = (1...visibleDayCount).compactMap { day -> TripDaySection? in
            guard let date = HolidayItineraryService.date(forTripDay: day, tripStart: tripStart) else {
                return nil
            }
            return TripDaySection(
                day: day,
                date: date,
                activities: activitiesByTripDay[day] ?? [],
                activitiesStartingOnDay: startingActivitiesByTripDay[day] ?? []
            )
        }

        return (sections, unscheduled)
    }

    static func isActivityStartDay(
        activity: HolidayActivity,
        holiday: Holiday,
        day: Date
    ) -> Bool {
        guard let start = resolvedStartDate(activity: activity, holiday: holiday) else { return false }
        return Calendar.current.isDate(start, inSameDayAs: day)
    }

    static func moveActivityToStartDate(
        _ activity: HolidayActivity,
        newStartDate: Date,
        holiday: Holiday
    ) {
        let calendar = Calendar.current
        let newStart = calendar.startOfDay(for: newStartDate)
        let currentStart = resolvedStartDate(activity: activity, holiday: holiday)
        let currentEnd = resolvedEndDate(activity: activity, holiday: holiday)

        if let currentStart, calendar.isDate(currentStart, inSameDayAs: newStart) {
            return
        }

        let spanDays: Int
        if let currentStart {
            let startDay = calendar.startOfDay(for: currentStart)
            let endDay = calendar.startOfDay(for: currentEnd ?? currentStart)
            spanDays = (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
        } else if activity.nights > 0 {
            spanDays = activity.nights
        } else {
            spanDays = 1
        }

        activity.plannedStartDate = newStart
        activity.estimateSource = .manual

        if spanDays > 1 {
            activity.plannedEndDate = calendar.date(byAdding: .day, value: spanDays - 1, to: newStart) ?? newStart
        } else {
            activity.plannedEndDate = nil
        }

        let components = calendar.dateComponents([.year, .month], from: newStart)
        if let year = components.year, let month = components.month {
            activity.plannedYear = year
            activity.plannedMonth = month
        }

        activity.markUpdated()
        holiday.markUpdated()
    }

    static func assignActivity(_ activity: HolidayActivity, toTripDay day: Int, holiday: Holiday) {
        guard let tripStart = holiday.plannedStartDate,
              let startDate = HolidayItineraryService.date(forTripDay: day, tripStart: tripStart) else {
            return
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        activity.plannedStartDate = start
        activity.estimateSource = .manual

        if activity.nights > 0 {
            activity.plannedEndDate = calendar.date(byAdding: .day, value: activity.nights - 1, to: start) ?? start
        } else {
            activity.plannedEndDate = nil
        }
        activity.markUpdated()
    }

    static func repositionActivity(
        _ activity: HolidayActivity,
        toTripDay day: Int,
        atIndex index: Int,
        holiday: Holiday
    ) {
        guard let tripLayout = tripDaySections(for: holiday) else { return }

        var startDaySections = tripLayout.0.map { section in
            TripDaySection(
                day: section.day,
                date: section.date,
                activities: section.activitiesStartingOnDay,
                activitiesStartingOnDay: section.activitiesStartingOnDay
            )
        }
        var unscheduled = tripLayout.unscheduled

        startDaySections = startDaySections.map { section in
            var copy = section
            copy.activities.removeAll { $0.id == activity.id }
            copy.activitiesStartingOnDay.removeAll { $0.id == activity.id }
            return copy
        }
        unscheduled.removeAll { $0.id == activity.id }

        if let tripStart = holiday.plannedStartDate,
           let currentStart = resolvedStartDate(activity: activity, holiday: holiday) {
            let currentDay = HolidayItineraryService.tripDay(for: currentStart, tripStart: tripStart)
            if currentDay != day {
                assignActivity(activity, toTripDay: day, holiday: holiday)
            }
        } else {
            assignActivity(activity, toTripDay: day, holiday: holiday)
        }

        guard let sectionIndex = startDaySections.firstIndex(where: { $0.day == day }) else { return }
        let insertIndex = min(max(index, 0), startDaySections[sectionIndex].activities.count)
        startDaySections[sectionIndex].activities.insert(activity, at: insertIndex)
        startDaySections[sectionIndex].activitiesStartingOnDay = startDaySections[sectionIndex].activities

        applySortOrders(from: startDaySections, unscheduled: unscheduled, holiday: holiday)
    }

    static func repositionActivityOnCalendarDay(
        _ activity: HolidayActivity,
        onDay day: Date,
        atIndex index: Int,
        holiday: Holiday
    ) {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: day)

        if let tripStart = holiday.plannedStartDate {
            let tripDay = HolidayItineraryService.tripDay(for: targetDay, tripStart: tripStart)
            repositionActivity(activity, toTripDay: tripDay, atIndex: index, holiday: holiday)
            return
        }

        var activitiesByStartDay: [Date: [HolidayActivity]] = [:]
        var undated: [HolidayActivity] = []

        for act in chronologicallySortedActivities(for: holiday) {
            guard let start = resolvedStartDate(activity: act, holiday: holiday) else {
                undated.append(act)
                continue
            }
            let startDay = calendar.startOfDay(for: start)
            activitiesByStartDay[startDay, default: []].append(act)
        }

        for key in activitiesByStartDay.keys {
            activitiesByStartDay[key]?.removeAll { $0.id == activity.id }
        }
        undated.removeAll { $0.id == activity.id }

        if let currentStart = resolvedStartDate(activity: activity, holiday: holiday) {
            if !calendar.isDate(currentStart, inSameDayAs: targetDay) {
                moveActivityToStartDate(activity, newStartDate: targetDay, holiday: holiday)
            }
        } else {
            moveActivityToStartDate(activity, newStartDate: targetDay, holiday: holiday)
        }

        var dayActivities = activitiesByStartDay[targetDay] ?? []
        let insertIndex = min(max(index, 0), dayActivities.count)
        dayActivities.insert(activity, at: insertIndex)
        activitiesByStartDay[targetDay] = dayActivities

        let sortedDays = activitiesByStartDay.keys.sorted()
        let ordered = sortedDays.flatMap { activitiesByStartDay[$0]! } + undated
        for (orderedIndex, act) in ordered.enumerated() {
            act.sortOrder = orderedIndex
            act.markUpdated()
        }
        holiday.markUpdated()
    }

    private static func applySortOrders(
        from sections: [TripDaySection],
        unscheduled: [HolidayActivity],
        holiday: Holiday
    ) {
        let ordered = sections.flatMap(\.activities) + unscheduled
        for (index, activity) in ordered.enumerated() {
            activity.sortOrder = index
            activity.markUpdated()
        }
        holiday.markUpdated()
    }

    static func calendarMonths(for holiday: Holiday) -> [(year: Int, month: Int)] {
        let calendar = Calendar.current
        var dates: [Date] = []
        if let start = holiday.plannedStartDate { dates.append(calendar.startOfDay(for: start)) }
        if let end = holiday.plannedEndDate { dates.append(calendar.startOfDay(for: end)) }

        for activity in holiday.activities {
            if let start = resolvedStartDate(activity: activity, holiday: holiday) {
                dates.append(start)
            }
            if let end = resolvedEndDate(activity: activity, holiday: holiday) {
                dates.append(end)
            }
        }

        guard let earliest = dates.min(), let latest = dates.max() else { return [] }

        var result: [(year: Int, month: Int)] = []
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: earliest))!
        let lastMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: latest))!

        while cursor <= lastMonth {
            let components = calendar.dateComponents([.year, .month], from: cursor)
            if let year = components.year, let month = components.month {
                result.append((year, month))
            }
            cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? cursor.addingTimeInterval(86400 * 32)
        }
        return result
    }

    static func assignSequentialDates(
        to activities: [HolidayActivity],
        startingFrom tripStart: Date,
        nights: [Int]
    ) {
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: tripStart)

        for (index, activity) in activities.enumerated() {
            let stayNights = index < nights.count ? nights[index] : 0
            activity.plannedStartDate = cursor

            if stayNights > 0 {
                let end = calendar.date(byAdding: .day, value: stayNights - 1, to: cursor) ?? cursor
                activity.plannedEndDate = end
                cursor = calendar.date(byAdding: .day, value: stayNights, to: cursor) ?? cursor
            } else {
                activity.plannedEndDate = nil
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            }
        }
    }

    static func chronologicallySortedActivities(for holiday: Holiday) -> [HolidayActivity] {
        let startDates = resolvedStartDates(for: holiday)
        return holiday.activities.sorted { lhs, rhs in
            compareChronologically(lhs, rhs, startDates: startDates)
        }
    }

    private static func resolvedDateMaps(for holiday: Holiday) -> (starts: [UUID: Date], ends: [UUID: Date]) {
        let calendar = Calendar.current
        var starts: [UUID: Date] = [:]
        var ends: [UUID: Date] = [:]
        var sequentialStarts: [UUID: Date] = [:]
        var sequentialEnds: [UUID: Date] = [:]

        if let tripStart = holiday.plannedStartDate {
            var cursor = calendar.startOfDay(for: tripStart)
            for candidate in holiday.sortedActivities {
                let start = cursor
                let end: Date
                if candidate.nights > 0 {
                    end = calendar.date(byAdding: .day, value: candidate.nights - 1, to: cursor) ?? cursor
                    cursor = calendar.date(byAdding: .day, value: candidate.nights, to: cursor) ?? cursor
                } else {
                    end = cursor
                    cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
                }
                sequentialStarts[candidate.id] = start
                sequentialEnds[candidate.id] = end
            }
        }

        for activity in holiday.activities {
            if usesExplicitActivityDates(activity), let start = activity.plannedStartDate {
                let startDay = calendar.startOfDay(for: start)
                starts[activity.id] = startDay
                if let end = activity.plannedEndDate {
                    ends[activity.id] = calendar.startOfDay(for: end)
                } else if activity.kind == .hotels, activity.nights > 1 {
                    ends[activity.id] = calendar.date(byAdding: .day, value: activity.nights - 1, to: startDay) ?? startDay
                } else {
                    ends[activity.id] = startDay
                }
            } else if let start = sequentialStarts[activity.id], let end = sequentialEnds[activity.id] {
                starts[activity.id] = start
                ends[activity.id] = end
            } else if let month = resolvedPlannedMonth(activity: activity, holiday: holiday) {
                let monthStart = PlanningCalendar.firstDayOfMonth(year: month.year, month: month.month)
                starts[activity.id] = monthStart
                ends[activity.id] = monthStart
            }
        }

        return (starts, ends)
    }

    private static func resolvedStartDates(for holiday: Holiday) -> [UUID: Date] {
        resolvedDateMaps(for: holiday).starts
    }

    private static func compareChronologically(
        _ lhs: HolidayActivity,
        _ rhs: HolidayActivity,
        startDates: [UUID: Date]
    ) -> Bool {
        let lhsDate = startDates[lhs.id]
        let rhsDate = startDates[rhs.id]

        switch (lhsDate, rhsDate) {
        case let (left?, right?):
            if left != right { return left < right }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case (nil, nil):
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
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

    static func importActivities(
        drafts: [HolidayActivityImportDraft],
        into holiday: Holiday,
        metadata: HolidayTripMetadataDraft?,
        replaceExisting: Bool,
        currency: AppCurrency,
        allTiles: [BudgetTile],
        in context: ModelContext
    ) throws {
        let included = drafts.filter(\.isIncluded)
        guard !included.isEmpty else { return }

        if replaceExisting {
            let activityIDs = Set(holiday.activities.map(\.id))
            for tile in allTiles where tile.linkedHolidayActivityId.map(activityIDs.contains) == true {
                context.delete(tile)
            }
            for activity in holiday.activities {
                context.delete(activity)
            }
            holiday.activities.removeAll()
        }

        if let metadata {
            if metadata.applyName, !metadata.name.isEmpty {
                holiday.name = metadata.name
            }
            if metadata.applyOrigin, !metadata.origin.isEmpty {
                holiday.origin = metadata.origin
            }
            if metadata.applyDestination, !metadata.destination.isEmpty {
                holiday.destination = metadata.destination
                if holiday.countryName.isEmpty {
                    holiday.countryName = metadata.destination
                }
            }
            if metadata.applyDuration, metadata.durationNights > 0, let start = holiday.plannedStartDate {
                let calendar = Calendar.current
                if let end = calendar.date(byAdding: .day, value: metadata.durationNights, to: start) {
                    holiday.plannedEndDate = end
                }
            }
        }

        var nextSortOrder = (holiday.activities.map(\.sortOrder).max() ?? -1) + 1
        for draft in included {
            let activity = HolidayActivity(name: draft.name, kind: draft.kind)
            activity.markCreated()
            activity.sortOrder = nextSortOrder
            nextSortOrder += 1
            activity.amountMinorUnits = MoneyFormatter.parseMajorUnits(draft.amountText, currency: currency) ?? 0
            activity.notes = draft.notes
            activity.estimateNote = draft.estimateNote
            activity.estimateSource = .aiSuggested
            activity.locationName = draft.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
            activity.nights = draft.nights
            activity.holiday = holiday
            context.insert(activity)
            holiday.activities.append(activity)
        }

        holiday.markUpdated()
        try context.save()

        if holiday.status == .committed {
            let settings = try AppDataService.ensureSettings(in: context)
            let months = try AppDataService.fetchMonths(settings: settings, in: context)
            let tiles = try AppDataService.fetchAllTiles(in: context)
            try syncCommittedHoliday(
                holiday: holiday,
                settings: settings,
                months: months,
                allTiles: tiles,
                in: context
            )
        } else {
            try AppDataService.refreshForecast(in: context)
        }
    }

    @discardableResult
    static func duplicateActivity(
        _ source: HolidayActivity,
        in holiday: Holiday,
        ontoDay day: Date? = nil,
        toTripDay tripDay: Int? = nil,
        atIndex: Int? = nil,
        in context: ModelContext
    ) throws -> HolidayActivity {
        let calendar = Calendar.current
        let targetIndex: Int
        if let day {
            let dayStart = calendar.startOfDay(for: day)
            targetIndex = atIndex ?? activitiesStarting(on: dayStart, holiday: holiday).count
        } else if let tripDay {
            let startDayCount = tripDaySections(for: holiday)?
                .0.first(where: { $0.day == tripDay })?
                .activitiesStartingOnDay
                .count ?? 0
            targetIndex = atIndex ?? startDayCount
        } else {
            targetIndex = atIndex ?? (holiday.activities.map(\.sortOrder).max() ?? -1) + 1
        }

        let copy = HolidayActivity(name: source.name, kind: source.kind)
        copy.markCreated()
        copy.amountMinorUnits = source.amountMinorUnits
        copy.notes = source.notes
        copy.estimateNote = source.estimateNote
        copy.estimateSource = .manual
        copy.locationName = source.locationName
        copy.countryName = source.countryName
        copy.latitude = source.latitude
        copy.longitude = source.longitude
        copy.geocodedSearchQuery = source.geocodedSearchQuery
        copy.nights = source.nights
        copy.linkedAccountId = source.linkedAccountId
        copy.subCategoryId = source.subCategoryId
        copy.plannedYear = source.plannedYear
        copy.plannedMonth = source.plannedMonth

        if let start = resolvedStartDate(activity: source, holiday: holiday) {
            copy.plannedStartDate = start
            if let end = resolvedEndDate(activity: source, holiday: holiday),
               !calendar.isDate(end, inSameDayAs: start) {
                copy.plannedEndDate = end
            }
        }

        copy.sortOrder = (holiday.activities.map(\.sortOrder).max() ?? -1) + 1
        copy.holiday = holiday
        context.insert(copy)
        holiday.activities.append(copy)

        if let day {
            repositionActivityOnCalendarDay(
                copy,
                onDay: calendar.startOfDay(for: day),
                atIndex: targetIndex,
                holiday: holiday
            )
        } else if let tripDay {
            repositionActivity(copy, toTripDay: tripDay, atIndex: targetIndex, holiday: holiday)
        }

        holiday.markUpdated()
        try context.save()

        if holiday.status == .committed {
            let settings = try AppDataService.ensureSettings(in: context)
            let months = try AppDataService.fetchMonths(settings: settings, in: context)
            let allTiles = try AppDataService.fetchAllTiles(in: context)
            try syncCommittedHoliday(
                holiday: holiday,
                settings: settings,
                months: months,
                allTiles: allTiles,
                in: context
            )
        } else {
            try AppDataService.refreshForecast(in: context)
        }

        return copy
    }

    static func deleteActivity(
        _ activity: HolidayActivity,
        from holiday: Holiday,
        allTiles: [BudgetTile],
        in context: ModelContext
    ) throws {
        if let tile = allTiles.first(where: { $0.linkedHolidayActivityId == activity.id }) {
            context.delete(tile)
        }
        context.delete(activity)
        holiday.markUpdated()
        try context.save()
        if holiday.status == .committed {
            let settings = try AppDataService.ensureSettings(in: context)
            let months = try AppDataService.fetchMonths(settings: settings, in: context)
            let tiles = try AppDataService.fetchAllTiles(in: context)
            try syncCommittedHoliday(
                holiday: holiday,
                settings: settings,
                months: months,
                allTiles: tiles,
                in: context
            )
        } else {
            try AppDataService.refreshForecast(in: context)
        }
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
