import Foundation
import SwiftData

@Model
final class BudgetTile {
    var id: UUID = UUID()
    var year: Int = 0
    var month: Int = 0
    var name: String = ""
    var amountMinorUnits: Int = 0
    var typeRaw: String = BudgetType.expense.rawValue
    var category: String = ""
    var sourceRaw: String = BudgetTileSource.manual.rawValue
    var statusRaw: String = BudgetTileStatus.active.rawValue
    var confidenceRaw: String = ConfidenceLevel.estimated.rawValue
    var commitmentRaw: String = CommitmentType.known.rawValue
    var linkedRuleId: UUID?
    var linkedHolidayActivityId: UUID?
    /// When nil, income/expenses use the primary (Main) account.
    var linkedAccountId: UUID?
    /// Destination account for transfers. Source is linkedAccountId (nil = Main).
    var transferToAccountId: UUID?
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deviceId: String = ""

    init(year: Int, month: Int, name: String = "") {
        self.year = year
        self.month = month
        self.name = name
    }

    var type: BudgetType {
        get { BudgetType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var source: BudgetTileSource {
        get { BudgetTileSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var status: BudgetTileStatus {
        get { BudgetTileStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var confidence: ConfidenceLevel {
        get { ConfidenceLevel(rawValue: confidenceRaw) ?? .estimated }
        set { confidenceRaw = newValue.rawValue }
    }

    var commitment: CommitmentType {
        get { CommitmentType(rawValue: commitmentRaw) ?? .known }
        set { commitmentRaw = newValue.rawValue }
    }

    var monthKey: String { "\(year)-\(month)" }

    var isActive: Bool { status == .active }
}
