import SwiftUI
import SwiftData

/// Picker for selecting which bank account a rule or tile applies to.
struct AccountPicker: View {
    @Query(sort: \BankAccount.displayOrder) private var accounts: [BankAccount]

    @Binding var linkedAccountId: UUID?
    var label: String = "Account"

    var body: some View {
        Picker(label, selection: $linkedAccountId) {
            if let primary = BankAccountService.primaryAccount(from: accounts) {
                Text(primary.name).tag(Optional<UUID>.none)
            }
            ForEach(secondaryAccounts) { account in
                Text(account.name).tag(Optional(account.id))
            }
        }
    }

    private var secondaryAccounts: [BankAccount] {
        accounts.filter { !$0.isPrimary }
    }
}

/// From / to account pickers for transfer rules and tiles.
struct TransferAccountFields: View {
    @Query(sort: \BankAccount.displayOrder) private var accounts: [BankAccount]

    @Binding var fromAccountId: UUID?
    @Binding var toAccountId: UUID?

    var body: some View {
        AccountPicker(linkedAccountId: $fromAccountId, label: "From account")

        Picker("To account", selection: $toAccountId) {
            Text("Select account").tag(Optional<UUID>.none)
            ForEach(destinationAccounts) { account in
                Text(account.name).tag(Optional(account.id))
            }
        }
    }

    private var destinationAccounts: [BankAccount] {
        let fromResolved = BankAccountService.resolvedAccountId(
            linkedAccountId: fromAccountId,
            accounts: accounts
        )
        return accounts.filter { $0.id != fromResolved }
    }
}

/// Filter picker for lists — includes an "All accounts" option.
struct AccountFilterPicker: View {
    @Query(sort: \BankAccount.displayOrder) private var accounts: [BankAccount]

    @Binding var filterAccountId: UUID?

    var body: some View {
        Picker("Account", selection: $filterAccountId) {
            Text("All accounts").tag(Optional<UUID>.none)
            ForEach(accounts) { account in
                Text(account.name).tag(Optional(account.id))
            }
        }
    }
}
