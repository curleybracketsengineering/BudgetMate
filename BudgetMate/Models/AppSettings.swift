import Foundation
import SwiftData

@Model
final class AppSettings {
    var id: UUID = UUID()
    var planningStartYear: Int = 2026
    var planningStartMonth: Int = 1
    var horizonMonths: Int = PlanningHorizon.baseMonths
    var startingBalanceMinorUnits: Int = 0
    var safeThresholdMinorUnits: Int = 5_000_00
    var warningThresholdMinorUnits: Int = 2_000_00
    var criticalThresholdMinorUnits: Int = 0
    var largePaymentThresholdMinorUnits: Int = 500_00
    /// ISO 4217 code stored as string for CloudKit compatibility (e.g. GBP, USD).
    var currencyCode: String = AppCurrency.GBP.rawValue
    var lastLocalSaveAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deviceId: String = ""

    init() {}

    var currency: AppCurrency {
        get { AppCurrency(rawValue: currencyCode) ?? .GBP }
        set { currencyCode = newValue.rawValue }
    }

    var planningStartDate: Date {
        PlanningCalendar.firstDayOfMonth(year: planningStartYear, month: planningStartMonth)
    }
}
