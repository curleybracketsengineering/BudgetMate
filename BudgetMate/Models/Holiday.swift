import Foundation
import SwiftData

@Model
final class Holiday {
    var id: UUID = UUID()
    var name: String = ""
    var destination: String = ""
    var origin: String = ""
    var notes: String = ""
    var plannedStartDate: Date?
    var plannedEndDate: Date?
    /// 0 means unset — use trip start date or per-activity month.
    var defaultPlannedYear: Int = 0
    var defaultPlannedMonth: Int = 0
    var statusRaw: String = HolidayStatus.draft.rawValue
    var committedAt: Date?
    var displayOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deviceId: String = ""

    @Relationship(deleteRule: .cascade, inverse: \HolidayActivity.holiday)
    var activities: [HolidayActivity] = []

    init(name: String = "") {
        self.name = name
    }

    var status: HolidayStatus {
        get { HolidayStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var sortedActivities: [HolidayActivity] {
        activities.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var dateRangeLabel: String? {
        guard let start = plannedStartDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if let end = plannedEndDate, end != start {
            return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        }
        return formatter.string(from: start)
    }
}
