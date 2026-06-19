import SwiftUI
import SwiftData

struct FirstRunSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var planningStartYear = Calendar.current.component(.year, from: .now)
    @State private var planningStartMonth = Calendar.current.component(.month, from: .now)
    @State private var startingBalanceText = "0.00"
    @State private var currency: AppCurrency = .GBP

    var body: some View {
        NavigationStack {
            Form {
                Section("Welcome to BudgetMate") {
                    Text("Set up your planning start point. You can change these later in Settings.")
                        .foregroundStyle(.secondary)
                }

                Section("Currency") {
                    Picker("Currency", selection: $currency) {
                        ForEach(AppCurrency.allCases) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                }

                Section {
                    PlanningStartPicker(month: $planningStartMonth, year: $planningStartYear)
                }

                Section("Starting balance") {
                    TextField("Amount", text: $startingBalanceText)
                    Text("This is the opening balance for your Main account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Get Started")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { saveAndContinue() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 400)
    }

    private func saveAndContinue() {
        let settings = AppSettings()
        settings.planningStartYear = planningStartYear
        settings.planningStartMonth = planningStartMonth
        settings.horizonMonths = PlanningHorizon.baseMonths
        settings.currency = currency
        let startingBalance = MoneyFormatter.parseMajorUnits(startingBalanceText, currency: currency) ?? 0
        settings.startingBalanceMinorUnits = startingBalance
        settings.markCreated()
        modelContext.insert(settings)

        let mainAccount = BankAccount(name: BankAccountService.primaryAccountName, isPrimary: true)
        mainAccount.startingBalanceMinorUnits = startingBalance
        mainAccount.markCreated()
        modelContext.insert(mainAccount)

        do {
            try AppDataService.reanchorPlan(settings: settings, in: modelContext)
            dismiss()
        } catch {
            print("First run setup failed: \(error)")
        }
    }
}
