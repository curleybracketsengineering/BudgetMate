import Foundation
import SwiftData

enum PayeeNoteService {
    static func index(_ notes: [PayeeNote]) -> [String: PayeeNote] {
        notes.keyedByMatchKey()
    }

    static func deduplicate(in context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<PayeeNote>())
        let grouped = Dictionary(grouping: all, by: \.matchKey)
        var changed = false

        for duplicates in grouped.values where duplicates.count > 1 {
            let keeper = duplicates.dropFirst().reduce(duplicates[0], PayeeNote.preferDuplicate)
            var groupChanged = false
            for duplicate in duplicates where duplicate !== keeper {
                if keeper.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !duplicate.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    keeper.displayName = duplicate.displayName
                }
                if keeper.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !duplicate.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    keeper.notes = duplicate.notes
                }
                if keeper.samplePayee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !duplicate.samplePayee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    keeper.samplePayee = duplicate.samplePayee
                }
                context.delete(duplicate)
                groupChanged = true
            }
            if groupChanged {
                keeper.markUpdated()
                changed = true
            }
        }

        if changed {
            try context.save()
        }
    }

    static func lookup(payee: String, in notes: [String: PayeeNote]) -> PayeeNote? {
        notes[PayeeNormalization.matchKey(payee)]
    }

    static func resolvedTitle(for payee: String, in notes: [String: PayeeNote]) -> String {
        let key = PayeeNormalization.matchKey(payee)
        if let note = notes[key], !note.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return note.displayName
        }
        return PayeeNormalization.displayName(from: payee)
    }

    static func resolvedPayeeLabels(
        for payee: String,
        in notes: [String: PayeeNote]
    ) -> (title: String, subtitle: String?) {
        let key = PayeeNormalization.matchKey(payee)
        if let note = notes[key], !note.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let bankLabel = note.samplePayee.isEmpty ? payee : note.samplePayee
            return (note.displayName, bankLabel)
        }
        return (payee, nil)
    }

    static func apply(to suggestion: inout BudgetSuggestion, payeeSample: String, notes: [String: PayeeNote]) {
        let key = PayeeNormalization.matchKey(payeeSample)
        suggestion.payeeMatchKey = key
        suggestion.bankPayeeSample = payeeSample

        guard let note = notes[key] else { return }

        let trimmedName = note.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            suggestion.name = trimmedName
        }
        suggestion.userNotes = note.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    static func upsert(
        matchKey: String,
        displayName: String,
        notes: String,
        samplePayee: String,
        in context: ModelContext
    ) throws -> PayeeNote {
        let trimmedKey = matchKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return PayeeNote() }

        try deduplicate(in: context)

        let descriptor = FetchDescriptor<PayeeNote>(
            predicate: #Predicate { $0.matchKey == trimmedKey }
        )
        let existing = try context.fetch(descriptor).first

        let note = existing ?? PayeeNote()
        if existing == nil {
            note.matchKey = trimmedKey
            note.markCreated()
            context.insert(note)
        } else {
            note.markUpdated()
        }

        note.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        note.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        note.samplePayee = samplePayee.trimmingCharacters(in: .whitespacesAndNewlines)

        try context.save()
        return note
    }

    static func note(for matchKey: String, in context: ModelContext) throws -> PayeeNote? {
        let key = matchKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        let descriptor = FetchDescriptor<PayeeNote>(
            predicate: #Predicate { $0.matchKey == key }
        )
        return try context.fetch(descriptor).first
    }
}
