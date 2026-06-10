import SwiftUI
import SwiftData

struct BankAccountFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let currency: AppCurrency
    var existingAccount: BankAccount?

    @State private var name = ""
    @State private var startingBalanceText = "0.00"
    @State private var importAlias = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                    TextField("Starting balance", text: $startingBalanceText)
                    TextField("Import alias (optional)", text: $importAlias)
                    Text("If your bank CSV uses a different account name, enter it here to auto-match imports.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existingAccount == nil ? "New Account" : "Edit Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadExisting() }
        }
        .frame(minWidth: 400, minHeight: 280)
    }

    private func loadExisting() {
        guard let account = existingAccount else { return }
        name = account.name
        startingBalanceText = MoneyFormatter.majorUnitsString(
            minorUnits: account.startingBalanceMinorUnits,
            currency: currency
        )
        importAlias = account.importAlias
    }

    private func save() {
        let account: BankAccount
        if let existingAccount {
            account = existingAccount
        } else {
            let allAccounts = (try? BankAccountService.fetchAll(in: modelContext)) ?? []
            account = BankAccount()
            account.displayOrder = allAccounts.count
            account.markCreated()
            modelContext.insert(account)
        }

        account.name = name.trimmingCharacters(in: .whitespaces)
        account.startingBalanceMinorUnits = MoneyFormatter.parseMajorUnits(startingBalanceText, currency: currency) ?? 0
        account.importAlias = importAlias.trimmingCharacters(in: .whitespaces)
        account.markUpdated()

        do {
            try AppDataService.refreshForecast(in: modelContext)
            dismiss()
        } catch {
            print("Account save failed: \(error)")
        }
    }
}
