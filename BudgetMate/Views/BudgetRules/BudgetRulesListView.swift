import SwiftUI
import SwiftData

struct BudgetRulesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(FeatureGateService.self) private var featureGate
    @Query(sort: \BudgetRule.name) private var rules: [BudgetRule]
    @Query private var settingsList: [AppSettings]
    @Query private var tiles: [BudgetTile]
    @Query(sort: \BankAccount.displayOrder) private var accounts: [BankAccount]

    @Binding var selectedRule: BudgetRule?
    @State private var searchText = ""
    @State private var showingNewRule = false
    @State private var newRuleTemplate: BudgetRuleStarterTemplate?
    @State private var showArchived = false
    @State private var rulePendingDeletion: BudgetRule?
    @State private var filterAccountId: UUID?
    @State private var generateAlert: GenerateTilesAlert?

    private var currency: AppCurrency { settingsList.first?.currency ?? .GBP }

    private var filteredRules: [BudgetRule] {
        rules.filter { rule in
            matchesArchiveFilter(rule) &&
            (searchText.isEmpty || rule.name.localizedCaseInsensitiveContains(searchText)) &&
            matchesAccountFilter(rule)
        }
    }

    /// Default (`showArchived == false`): live rules only. Archived mode: archived rules only.
    private func matchesArchiveFilter(_ rule: BudgetRule) -> Bool {
        showArchived ? rule.isArchived : !rule.isArchived
    }

    private func matchesAccountFilter(_ rule: BudgetRule) -> Bool {
        guard let filterAccountId else { return true }
        let sourceId = BankAccountService.resolvedAccountId(
            linkedAccountId: rule.linkedAccountId,
            accounts: accounts
        )
        if rule.type == .transfer {
            return sourceId == filterAccountId || rule.transferToAccountId == filterAccountId
        }
        return sourceId == filterAccountId
    }

    private var activeRules: [BudgetRule] {
        filteredRules.filter { $0.isActive && !$0.isArchived }
    }

    private var summary: BudgetRuleService.Summary {
        BudgetRuleService.summary(for: filteredRules)
    }

    private var expiringRules: [BudgetRule] {
        BudgetRuleService.expiringSoon(from: filteredRules)
    }

    private var showExpiryWarnings: Bool {
        featureGate.isAvailable(.ruleExpiryWarnings) && !expiringRules.isEmpty
    }

    private var incomingRules: [BudgetRule] {
        filteredRules.filter { $0.type == .income }
    }

    private var outgoingRules: [BudgetRule] {
        filteredRules.filter { $0.type == .expense || $0.type == .saving }
    }

    private var otherRules: [BudgetRule] {
        filteredRules.filter { $0.type == .transfer || $0.type == .adjustment }
    }

    private var hasAnyRules: Bool {
        !rules.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            mainContent
        }
        .navigationTitle("Budget Rules")
        .searchable(text: $searchText, prompt: "Search rules")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingNewRule, onDismiss: { newRuleTemplate = nil }) {
            BudgetRuleFormView(currency: currency, template: newRuleTemplate)
        }
        .onChange(of: showArchived) {
            if let selectedRule, !matchesArchiveFilter(selectedRule) {
                self.selectedRule = nil
            }
        }
        .confirmationDialog(
            "Delete this rule permanently?",
            isPresented: Binding(
                get: { rulePendingDeletion != nil },
                set: { if !$0 { rulePendingDeletion = nil } }
            ),
            presenting: rulePendingDeletion
        ) { rule in
            Button("Delete Permanently", role: .destructive) {
                deletePermanently(rule)
            }
            Button("Cancel", role: .cancel) {
                rulePendingDeletion = nil
            }
        } message: { rule in
            Text(deleteConfirmationMessage(for: rule))
        }
        .alert(item: $generateAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recurring blueprint")
                    .font(.title2.weight(.semibold))
                Text("Rules are recurring income and expenses. They generate tiles in your monthly plan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if hasAnyRules && !showArchived {
                summarySection
            }

            if !showArchived && showExpiryWarnings {
                expiryBanner
            }

            if accounts.count > 1 {
                AccountFilterPicker(filterAccountId: $filterAccountId)
                    .frame(maxWidth: 240)
            }

            Toggle("Show archived", isOn: $showArchived)
                .toggleStyle(.switch)
                .font(.subheadline)
        }
        .padding()
    }

    private var summarySection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 10) {
            SummaryCard(
                title: "Active rules",
                amount: "\(summary.activeCount)"
            )
            SummaryCard(
                title: "Income / month",
                amount: MoneyFormatter.format(minorUnits: summary.incomeMinorUnits, currency: currency),
                tint: .green
            )
            SummaryCard(
                title: "Bills / month",
                amount: MoneyFormatter.format(minorUnits: summary.expenseMinorUnits, currency: currency),
                tint: .red
            )
            if summary.savingMinorUnits > 0 {
                SummaryCard(
                    title: "Savings / month",
                    amount: MoneyFormatter.format(minorUnits: summary.savingMinorUnits, currency: currency)
                )
            }
            SummaryCard(
                title: "Net / month",
                amount: MoneyFormatter.format(minorUnits: summary.netMinorUnits, currency: currency),
                tint: summary.netMinorUnits >= 0 ? .green : .red
            )
        }
    }

    private var expiryBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("\(expiringRules.count) rule\(expiringRules.count == 1 ? "" : "s") ending within 3 months.")
                .font(.subheadline)
            Spacer()
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var mainContent: some View {
        if !hasAnyRules {
            BudgetRulesEmptyState(onNewRule: { showingNewRule = true }, onTemplate: startFromTemplate)
        } else {
            rulesList
        }
    }

    private var rulesList: some View {
        List(selection: $selectedRule) {
            if !incomingRules.isEmpty {
                Section("Incoming") {
                    ForEach(incomingRules, id: \.id) { rule in
                        ruleRow(rule)
                    }
                }
            }

            if !outgoingRules.isEmpty {
                Section("Outgoing") {
                    ForEach(outgoingRules, id: \.id) { rule in
                        ruleRow(rule)
                    }
                }
            }

            if !otherRules.isEmpty {
                Section("Other") {
                    ForEach(otherRules, id: \.id) { rule in
                        ruleRow(rule)
                    }
                }
            }

            if filteredRules.isEmpty {
                ContentUnavailableView(
                    "No matching rules",
                    systemImage: "magnifyingglass",
                    description: Text(showArchived
                        ? "Try a different search."
                        : "Try a different search or show archived rules.")
                )
            }
        }
    }

    private func ruleRow(_ rule: BudgetRule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.name)
                    if BudgetRuleService.isExpiringSoon(rule), featureGate.isAvailable(.ruleExpiryWarnings) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Text(ruleSubtitle(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if rule.isArchived {
                Text("Archived")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .tag(rule)
        .contextMenu {
            if rule.isArchived {
                Button("Restore") { restore(rule) }
                Divider()
                Button("Delete Permanently", role: .destructive) {
                    rulePendingDeletion = rule
                }
            } else {
                Button("Archive") { archive(rule) }
            }
        }
    }

    private func ruleSubtitle(_ rule: BudgetRule) -> String {
        let monthly = MoneyFormatter.format(
            minorUnits: BudgetRuleService.monthlyEquivalent(for: rule),
            currency: currency
        )
        var parts = ["\(rule.cycle.displayName)", "\(monthly) / month"]
        if !rule.showIndividuallyInPlan, rule.type == .income || rule.type == .expense || rule.type == .saving {
            parts.append("Grouped in plan")
        }
        if accounts.count > 1 {
            if rule.type == .transfer,
               let transfer = BankAccountService.transferDescription(
                   from: rule.linkedAccountId,
                   to: rule.transferToAccountId,
                   accounts: accounts
               ) {
                parts.append(transfer)
            } else {
                parts.append(BankAccountService.accountName(for: rule.linkedAccountId, accounts: accounts))
            }
        }
        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showingNewRule = true
            } label: {
                Label("New Rule", systemImage: "plus")
            }

            Button {
                generateTiles()
            } label: {
                Label("Generate Tiles", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Create forecast tiles from active rules across your planning horizon.")

            if let selectedRule {
                if selectedRule.isArchived {
                    Button("Restore") { restore(selectedRule) }
                    Button("Delete Permanently", role: .destructive) {
                        rulePendingDeletion = selectedRule
                    }
                } else {
                    Button("Archive") { archive(selectedRule) }
                }
            }
        }
    }

    private func startFromTemplate(_ template: BudgetRuleStarterTemplate) {
        newRuleTemplate = template
        showingNewRule = true
    }

    private func archive(_ rule: BudgetRule) {
        rule.isArchived = true
        rule.isActive = false
        rule.markUpdated()
        if selectedRule?.id == rule.id {
            selectedRule = nil
        }
        try? modelContext.save()
    }

    private func restore(_ rule: BudgetRule) {
        rule.isArchived = false
        rule.isActive = true
        rule.markUpdated()
        try? modelContext.save()
    }

    private func deleteConfirmationMessage(for rule: BudgetRule) -> String {
        let tileCount = BudgetRuleService.recurringTiles(for: rule, in: tiles).count
        if tileCount > 0 {
            return """
            This will permanently remove "\(rule.name)" and \(tileCount) linked recurring tile\(tileCount == 1 ? "" : "s") from your plan. This cannot be undone.
            """
        }
        return "This will permanently remove \"\(rule.name)\". This cannot be undone."
    }

    private func deletePermanently(_ rule: BudgetRule) {
        do {
            try BudgetRuleService.deletePermanently(rule: rule, tiles: tiles, in: modelContext)
            if selectedRule?.id == rule.id {
                selectedRule = nil
            }
            rulePendingDeletion = nil
            try AppDataService.refreshForecast(in: modelContext)
        } catch {
            print("Delete rule failed: \(error)")
        }
    }

    private func generateTiles() {
        do {
            let created = try AppDataService.generateAndRefresh(in: modelContext)
            if created == 0 {
                generateAlert = GenerateTilesAlert(
                    title: "No new tiles",
                    message: generateTilesEmptyMessage
                )
            } else {
                generateAlert = GenerateTilesAlert(
                    title: "Tiles generated",
                    message: "Added \(created) tile\(created == 1 ? "" : "s") to your monthly plan."
                )
            }
        } catch {
            generateAlert = GenerateTilesAlert(
                title: "Generate failed",
                message: error.localizedDescription
            )
        }
    }

    private var generateTilesEmptyMessage: String {
        guard let settings = settingsList.first else {
            return "Could not read plan settings."
        }
        return BudgetRuleService.generateTilesEmptyMessage(for: rules, settings: settings)
    }
}

private struct GenerateTilesAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct BudgetRulesEmptyState: View {
    let onNewRule: () -> Void
    let onTemplate: (BudgetRuleStarterTemplate) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ContentUnavailableView(
                    "No budget rules yet",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text("Add recurring income and expenses here. They'll generate tiles in your monthly plan.")
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Get started")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        stepRow(number: 1, text: "Import bank history, select suggestions, and confirm save in Imports")
                        stepRow(number: 2, text: "Or add a few core rules using the templates below")
                        stepRow(number: 3, text: "Tap Generate Tiles to fill your monthly plan")
                    }
                }
                .frame(maxWidth: 480, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick templates")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                        ForEach(BudgetRuleStarterTemplate.all) { template in
                            Button {
                                onTemplate(template)
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: template.systemImage)
                                        .font(.title2)
                                    Text(template.name)
                                        .font(.caption.weight(.medium))
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: 480)

                Button {
                    onNewRule()
                } label: {
                    Label("New blank rule", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
