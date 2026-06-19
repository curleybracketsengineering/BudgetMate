import Foundation
import SwiftData

@Model
final class HolidayActivity {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = HolidayActivityKind.other.rawValue
    var amountMinorUnits: Int = 0
    /// 0 means inherit from holiday default or trip start month.
    var plannedYear: Int = 0
    var plannedMonth: Int = 0
    var linkedAccountId: UUID?
    var subCategoryId: UUID?
    var sortOrder: Int = 0
    var notes: String = ""
    var estimateSourceRaw: String = HolidayActivityEstimateSource.manual.rawValue
    var estimateNote: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deviceId: String = ""

    var holiday: Holiday?

    init(name: String = "", kind: HolidayActivityKind = .other) {
        self.name = name
        self.kindRaw = kind.rawValue
    }

    var kind: HolidayActivityKind {
        get { HolidayActivityKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var estimateSource: HolidayActivityEstimateSource {
        get { HolidayActivityEstimateSource(rawValue: estimateSourceRaw) ?? .manual }
        set { estimateSourceRaw = newValue.rawValue }
    }
}
