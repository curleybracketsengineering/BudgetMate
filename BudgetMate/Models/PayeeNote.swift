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

    /// When multiple records share a matchKey, keep the labelled one, or the most recently updated.
    static func preferDuplicate(_ existing: PayeeNote, _ duplicate: PayeeNote) -> PayeeNote {
        let existingNamed = !existing.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let duplicateNamed = !duplicate.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if existingNamed != duplicateNamed {
            return existingNamed ? existing : duplicate
        }
        let existingHasNotes = !existing.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let duplicateHasNotes = !duplicate.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if existingHasNotes != duplicateHasNotes {
            return existingHasNotes ? existing : duplicate
        }
        return existing.updatedAt >= duplicate.updatedAt ? existing : duplicate
    }
}

extension Array where Element == PayeeNote {
    func keyedByMatchKey() -> [String: PayeeNote] {
        Dictionary(map { ($0.matchKey, $0) }, uniquingKeysWith: PayeeNote.preferDuplicate)
    }
}
