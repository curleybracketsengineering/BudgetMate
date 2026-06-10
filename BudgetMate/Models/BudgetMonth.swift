import Foundation
import SwiftData

@Model
final class BudgetMonth {
    var id: UUID = UUID()
    var year: Int = 0
    var month: Int = 0
    var openingBalanceMinorUnits: Int = 0
    var closingBalanceMinorUnits: Int = 0
    var isLocked: Bool = false
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deviceId: String = ""

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    var monthKey: String { "\(year)-\(month)" }

    var displayTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else {
            return "\(month)/\(year)"
        }
        return formatter.string(from: date)
    }
}
