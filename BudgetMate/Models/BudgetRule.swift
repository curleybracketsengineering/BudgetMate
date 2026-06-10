import Foundation
import SwiftData

@Model
final class BudgetRule {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = BudgetType.expense.rawValue
    var category: String = ""
    var amountMinorUnits: Int = 0
    var cycleRaw: String = BudgetCycleType.monthly.rawValue
    var startDate: Date = Date()
    var endDate: Date?
    var isActive: Bool = true
    var isArchived: Bool = false
    var confidenceRaw: String = ConfidenceLevel.estimated.rawValue
    var commitmentRaw: String = CommitmentType.known.rawValue
    var assumptionsNotes: String = ""
    /// Comma-separated calendar months (1–12) when cycle is tenMonthly, e.g. "4,5,6,7,8,9,10,11,12,1"
    var monthPatternRaw: String = ""
    /// When nil, income/expenses use the primary (Main) account.
    var linkedAccountId: UUID?
    /// Destination account for transfers. Source is linkedAccountId (nil = Main).
    var transferToAccountId: UUID?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deviceId: String = ""

    init() {}

    var type: BudgetType {
        get { BudgetType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var cycle: BudgetCycleType {
        get { BudgetCycleType(rawValue: cycleRaw) ?? .monthly }
        set { cycleRaw = newValue.rawValue }
    }

    var confidence: ConfidenceLevel {
        get { ConfidenceLevel(rawValue: confidenceRaw) ?? .estimated }
        set { confidenceRaw = newValue.rawValue }
    }

    var commitment: CommitmentType {
        get { CommitmentType(rawValue: commitmentRaw) ?? .known }
        set { commitmentRaw = newValue.rawValue }
    }
}
