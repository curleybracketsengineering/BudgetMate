import Foundation

enum PlanningHorizon {
    static let monthsPerYear = 12
    static let baseYears = 3
    static let baseMonths = baseYears * monthsPerYear

    static func years(from months: Int) -> Int {
        months / monthsPerYear
    }

    static func months(forYears years: Int) -> Int {
        years * monthsPerYear
    }

    static func label(forMonths months: Int) -> String {
        guard months > 0 else { return "No months" }
        if months % monthsPerYear == 0 {
            let years = months / monthsPerYear
            return years == 1 ? "1 year" : "\(years) years"
        }
        return "\(months) months"
    }
}
