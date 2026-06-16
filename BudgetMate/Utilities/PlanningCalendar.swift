import Foundation

enum PlanningCalendar {
    static func monthSequence(
        startYear: Int,
        startMonth: Int,
        count: Int
    ) -> [(year: Int, month: Int)] {
        guard count > 0 else { return [] }
        var result: [(year: Int, month: Int)] = []
        var year = startYear
        var month = startMonth
        for _ in 0..<count {
            result.append((year, month))
            month += 1
            if month > 12 {
                month = 1
                year += 1
            }
        }
        return result
    }

    static func firstDayOfMonth(year: Int, month: Int, calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return calendar.date(from: components) ?? .now
    }

    static func compare(year1: Int, month1: Int, to year2: Int, month2: Int) -> ComparisonResult {
        if year1 != year2 { return year1 < year2 ? .orderedAscending : .orderedDescending }
        if month1 != month2 { return month1 < month2 ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    static func contains(
        year: Int,
        month: Int,
        in date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let components = calendar.dateComponents([.year, .month], from: date)
        return components.year == year && components.month == month
    }

    static func monthsBetween(
        from start: Date,
        to targetYear: Int,
        targetMonth: Int,
        calendar: Calendar = .current
    ) -> Int? {
        var targetComponents = DateComponents()
        targetComponents.year = targetYear
        targetComponents.month = targetMonth
        targetComponents.day = 1
        guard let targetDate = calendar.date(from: targetComponents) else { return nil }
        let startComponents = calendar.dateComponents([.year, .month], from: start)
        guard let startYear = startComponents.year, let startMonth = startComponents.month else { return nil }
        return (targetYear - startYear) * 12 + (targetMonth - startMonth)
    }
}
