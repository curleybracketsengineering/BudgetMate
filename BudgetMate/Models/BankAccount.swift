import Foundation
import SwiftData

@Model
final class BankAccount {
    var id: UUID = UUID()
    var name: String = ""
    /// Opening balance for this account at the start of the planning horizon.
    var startingBalanceMinorUnits: Int = 0
    /// The default account for income and expenses when no account is specified.
    var isPrimary: Bool = false
    var displayOrder: Int = 0
    /// Optional alias for matching bank CSV account names during import.
    var importAlias: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deviceId: String = ""

    init(name: String = "", isPrimary: Bool = false) {
        self.name = name
        self.isPrimary = isPrimary
    }
}
