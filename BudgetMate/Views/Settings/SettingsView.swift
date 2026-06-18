import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(FeatureGateService.self) private var featureGate
    @Query private var settingsList: [AppSettings]
    @Query(sort: \BankAccount.displayOrder) private var accounts: [BankAccount]

    @State private var planningStartMonth = 1
    @State private var planningStartYear = 2026
    @State private var horizonMonths = PlanningHorizon.baseMonths
    @State private var startingBalanceText = ""
    @State private var safeThresholdText = ""
    @State private var warningThresholdText = ""
    @State private var criticalThresholdText = ""
    @State private var largePaymentText = ""
    @State private var currency: AppCurrency = .GBP
    @State private var didLoad = false
    @State private var showingNewAccount = false
    @State private var editingAccount: BankAccount?
    @State private var showingClearDataConfirmation = false
    @State private var showingStartAgain = false
    @FocusState private var focusedMoneyField: MoneyField?

    private var settings: AppSettings? { settingsList.first }

    private enum MoneyField: Hashable {
        case startingBalance
        case safeThreshold
        case warningThreshold
        case criticalThreshold
        case largePayment
    }

    var body: some View {
        Form {
            if let settings {
                bankAccountsSection(settings)
                planningSection(settings)
                thresholdsSection(settings)
                currencySection
                proSection
                iCloudSection(settings)
                startAgainSection
            } else {
                Text("No settings found. Restart the app to run setup.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { loadFromSettings() }
        .onDisappear {
            guard didLoad else { return }
            save(settings)
        }
        .onChange(of: planningStartMonth) { save(settings) }
        .onChange(of: planningStartYear) { save(settings) }
        .onChange(of: horizonMonths) { save(settings) }
        .onChange(of: currency) { save(settings) }
        .onChange(of: focusedMoneyField) { previous, _ in
            if previous != nil {
                save(settings)
            }
        }
        .sheet(isPresented: $showingNewAccount) {
            BankAccountFormView(currency: currency)
        }
        .sheet(item: $editingAccount, onDismiss: reloadStartingBalanceFromStore) { account in
            BankAccountFormView(currency: currency, existingAccount: account)
        }
        .sheet(isPresented: $showingStartAgain, onDismiss: reloadAfterStartAgain) {
            FirstRunSetupView()
        }
        .confirmationDialog(
            "Clear all data?",
            isPresented: $showingClearDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear and start again", role: .destructive) {
                clearAllDataAndStartAgain()
            }
        } message: {
            Text("This permanently deletes all budget data on this device — accounts, rules, months, and imports. If iCloud sync is on, the reset will sync to your other devices.")
        }
    }

    @ViewBuilder
    private func bankAccountsSection(_ settings: AppSettings) -> some View {
        Section("Bank accounts") {
            ForEach(accounts) { account in
                Button {
                    editingAccount = account
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(account.name)
                                if account.isPrimary {
                                    Text("Primary")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                                }
                            }
                            Text(MoneyFormatter.format(minorUnits: account.startingBalanceMinorUnits, currency: currency))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if account.isPrimary {
                                Text("Tap to edit, or change in Planning below.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                showingNewAccount = true
            } label: {
                Label("Add account", systemImage: "plus")
            }

            Text("Income and expenses default to your Main account. Assign specific rules — like holiday savings or car costs — to secondary accounts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func planningSection(_ settings: AppSettings) -> some View {
        Section("Planning") {
            PlanningStartPicker(month: $planningStartMonth, year: $planningStartYear)

            Picker("Plan length", selection: $horizonMonths) {
                ForEach(featureGate.allowedHorizons(), id: \.self) { months in
                    Text(PlanningHorizon.label(forMonths: months)).tag(months)
                }
            }
            .disabled(featureGate.allowedHorizons().count == 1)

            Text("Your plan includes \(PlanningHorizon.baseYears) years by default. Pro unlocks extra years up to 10.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("Starting balance") {
                CurrencyAmountField(currency: currency, text: $startingBalanceText) {
                    save(settings)
                }
                .focused($focusedMoneyField, equals: .startingBalance)
            }
            Text("Opening balance for your Main account.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func thresholdsSection(_ settings: AppSettings) -> some View {
        Section("Balance thresholds") {
            thresholdField("Safe", focus: .safeThreshold, text: $safeThresholdText, settings: settings)
            thresholdField("Warning", focus: .warningThreshold, text: $warningThresholdText, settings: settings)
            thresholdField("Critical", focus: .criticalThreshold, text: $criticalThresholdText, settings: settings)
            thresholdField("Large payment", focus: .largePayment, text: $largePaymentText, settings: settings)
        }
    }

    private var currencySection: some View {
        Section("Currency") {
            Picker("Display currency", selection: $currency) {
                ForEach(AppCurrency.allCases) { c in
                    Text(c.displayName).tag(c)
                }
            }
        }
    }

    private var proSection: some View {
        Section("Pro unlock (dev)") {
            Toggle("Pro unlocked", isOn: Bindable(featureGate).isProUnlocked)
            Text("StoreKit integration comes later. Toggle for testing Pro features.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var startAgainSection: some View {
        Section("Start again") {
            Button("Clear all data and start again", role: .destructive) {
                showingClearDataConfirmation = true
            }
            Text("Removes everything and walks you through setup from scratch.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func iCloudSection(_ settings: AppSettings) -> some View {
        Section("iCloud sync") {
            LabeledContent("Status") {
                Text("Enabled — automatic sync")
                    .foregroundStyle(.secondary)
            }
            if let lastSave = settings.lastLocalSaveAt {
                LabeledContent("Last local save") {
                    Text(lastSave.formatted(date: .abbreviated, time: .shortened))
                }
            }
            LabeledContent("Device") {
                Text(UpdatedAtTracker.currentDeviceId)
                    .foregroundStyle(.secondary)
            }
            Text("Sync uses your private iCloud account and may take a moment. No manual sync is needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func thresholdField(
        _ label: String,
        focus: MoneyField,
        text: Binding<String>,
        settings: AppSettings
    ) -> some View {
        LabeledContent(label) {
            CurrencyAmountField(currency: currency, text: text) {
                save(settings)
            }
            .focused($focusedMoneyField, equals: focus)
        }
    }

    private func reloadStartingBalanceFromStore() {
        guard let settings else { return }
        startingBalanceText = MoneyFormatter.majorUnitsString(
            minorUnits: settings.startingBalanceMinorUnits,
            currency: currency
        )
    }

    private func reloadAfterStartAgain() {
        didLoad = false
        loadFromSettings()
    }

    private func clearAllDataAndStartAgain() {
        do {
            try AppDataService.clearAllData(in: modelContext)
            didLoad = false
            showingStartAgain = true
        } catch {
            print("Clear all data failed: \(error)")
        }
    }

    private func loadFromSettings() {
        guard let settings, !didLoad else { return }
        didLoad = true
        planningStartMonth = settings.planningStartMonth
        planningStartYear = settings.planningStartYear
        horizonMonths = featureGate.normalizedHorizon(settings.horizonMonths)
        currency = settings.currency
        startingBalanceText = MoneyFormatter.majorUnitsString(minorUnits: settings.startingBalanceMinorUnits, currency: currency)
        safeThresholdText = MoneyFormatter.majorUnitsString(minorUnits: settings.safeThresholdMinorUnits, currency: currency)
        warningThresholdText = MoneyFormatter.majorUnitsString(minorUnits: settings.warningThresholdMinorUnits, currency: currency)
        criticalThresholdText = MoneyFormatter.majorUnitsString(minorUnits: settings.criticalThresholdMinorUnits, currency: currency)
        largePaymentText = MoneyFormatter.majorUnitsString(minorUnits: settings.largePaymentThresholdMinorUnits, currency: currency)
    }

    private func save(_ settings: AppSettings?) {
        guard let settings else { return }
        settings.planningStartMonth = planningStartMonth
        settings.planningStartYear = planningStartYear
        settings.horizonMonths = featureGate.normalizedHorizon(horizonMonths)
        settings.currency = currency
        settings.startingBalanceMinorUnits = MoneyFormatter.parseMajorUnits(startingBalanceText, currency: currency) ?? settings.startingBalanceMinorUnits
        if let primary = BankAccountService.primaryAccount(from: accounts) {
            primary.startingBalanceMinorUnits = settings.startingBalanceMinorUnits
            primary.markUpdated()
        }
        settings.safeThresholdMinorUnits = MoneyFormatter.parseMajorUnits(safeThresholdText, currency: currency) ?? settings.safeThresholdMinorUnits
        settings.warningThresholdMinorUnits = MoneyFormatter.parseMajorUnits(warningThresholdText, currency: currency) ?? settings.warningThresholdMinorUnits
        settings.criticalThresholdMinorUnits = MoneyFormatter.parseMajorUnits(criticalThresholdText, currency: currency) ?? settings.criticalThresholdMinorUnits
        settings.largePaymentThresholdMinorUnits = MoneyFormatter.parseMajorUnits(largePaymentText, currency: currency) ?? settings.largePaymentThresholdMinorUnits
        settings.markUpdated()

        do {
            _ = try AppDataService.ensureMonths(settings: settings, in: modelContext)
            try AppDataService.refreshForecast(in: modelContext)
        } catch {
            print("Settings save failed: \(error)")
        }
    }
}
