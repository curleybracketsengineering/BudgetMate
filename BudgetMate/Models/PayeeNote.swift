import Foundation
import SwiftData

@Model
final class PayeeNote {
    var id: UUID = UUID()
    /// Normalized payee string used to match bank imports.
    var matchKey: String = ""
    var displayName: String = ""
    var notes: String = ""
    /// Most recent raw payee text from the bank feed.
    var samplePayee: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deviceId: String = ""

    init() {}
}
