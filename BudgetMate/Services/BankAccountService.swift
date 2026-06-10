import Foundation
import SwiftData

enum BankAccountService {
    static let primaryAccountName = "Main"

    static func fetchAll(in context: ModelContext) throws -> [BankAccount] {
        let descriptor = FetchDescriptor<BankAccount>(
            sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    static func primaryAccount(from accounts: [BankAccount]) -> BankAccount? {
        accounts.first(where: \.isPrimary) ?? accounts.first
    }

    /// Ensures a primary "Main" account exists. Migrates existing AppSettings balance on first run.
    @discardableResult
    static func ensurePrimaryAccount(
        settings: AppSettings,
        in context: ModelContext
    ) throws -> BankAccount {
        let accounts = try fetchAll(in: context)
        if let primary = primaryAccount(from: accounts) {
            return primary
        }

        let main = BankAccount(name: primaryAccountName, isPrimary: true)
        main.startingBalanceMinorUnits = settings.startingBalanceMinorUnits
        main.displayOrder = 0
        main.markCreated()
        context.insert(main)
        try context.save()
        return main
    }

    /// Resolves which account a tile or rule belongs to. Nil linkedAccountId means the primary account.
    static func resolvedAccountId(
        linkedAccountId: UUID?,
        accounts: [BankAccount]
    ) -> UUID? {
        if let linkedAccountId {
            return linkedAccountId
        }
        return primaryAccount(from: accounts)?.id
    }

    static func accountName(
        for linkedAccountId: UUID?,
        accounts: [BankAccount]
    ) -> String {
        if let linkedAccountId,
           let account = accounts.first(where: { $0.id == linkedAccountId }) {
            return account.name
        }
        return primaryAccount(from: accounts)?.name ?? primaryAccountName
    }

    static func accountForImportAlias(
        _ alias: String,
        accounts: [BankAccount]
    ) -> BankAccount? {
        let trimmed = alias.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let match = accounts.first(where: {
            !$0.importAlias.isEmpty &&
            $0.importAlias.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return match
        }

        if let match = accounts.first(where: {
            $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return match
        }

        return nil
    }

    static func accountName(for accountId: UUID, accounts: [BankAccount]) -> String {
        accounts.first(where: { $0.id == accountId })?.name ?? primaryAccountName
    }

    static func transferDescription(
        from linkedAccountId: UUID?,
        to transferToAccountId: UUID?,
        accounts: [BankAccount]
    ) -> String? {
        guard let transferToAccountId else { return nil }
        let fromName = accountName(for: linkedAccountId, accounts: accounts)
        let toName = accountName(for: transferToAccountId, accounts: accounts)
        return "\(fromName) → \(toName)"
    }
}
