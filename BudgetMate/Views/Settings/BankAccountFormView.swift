import SwiftUI
import SwiftData

struct BankAccountFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    let currency: AppCurrency
    var existingAccount: BankAccount?

    @State private var name = ""
    @State private var startingBalanceText = "0.00"
    @State private var importAlias = ""

    private var isPrimary: Bool { existingAccount?.isPrimary == true }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if isPrimary {
                        LabeledContent("Name") {
                            Text(name)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        TextField("Name", text: $name)
                    }

                    LabeledContent("Starting balance") {
                        CurrencyAmountField(currency: currency, text: $startingBalanceText)
                    }

                    if !isPrimary {
                        TextField("Import alias (optional)", text: $importAlias)
                        Text("If your bank CSV uses a different account name, enter it here to auto-match imports.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isPrimary {
                    Section {
                        Text("This is your default account for income and expenses. You can also edit the starting balance in Settings → Planning.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isPrimary && name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadExisting() }
        }
        .frame(minWidth: 400, minHeight: isPrimary ? 240 : 280)
    }

    private var navigationTitle: String {
        if isPrimary {
            return "Main Account"
        }
        return existingAccount == nil ? "New Account" : "Edit Account"
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

        if !isPrimary {
            account.name = name.trimmingCharacters(in: .whitespaces)
            account.importAlias = importAlias.trimmingCharacters(in: .whitespaces)
        }

        let startingBalance = MoneyFormatter.parseMajorUnits(startingBalanceText, currency: currency) ?? 0
        account.startingBalanceMinorUnits = startingBalance
        account.markUpdated()

        if isPrimary, let settings = settingsList.first {
            settings.startingBalanceMinorUnits = startingBalance
            settings.markUpdated()
        }

        do {
            try AppDataService.refreshForecast(in: modelContext)
            dismiss()
        } catch {
            print("Account save failed: \(error)")
        }
    }
}
