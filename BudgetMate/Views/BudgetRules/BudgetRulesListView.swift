import SwiftUI
import SwiftData

struct BudgetRulesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(FeatureGateService.self) private var featureGate
    @Query(sort: [SortDescriptor(\BudgetRule.displayOrder), SortDescriptor(\BudgetRule.name)]) private var rules: [BudgetRule]
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

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredRules: [BudgetRule] {
        rules.filter { rule in
            matchesArchiveFilter(rule) &&
            matchesSearchFilter(rule) &&
            matchesAccountFilter(rule)
        }
    }

    private func matchesSearchFilter(_ rule: BudgetRule) -> Bool {
        let query = trimmedSearchText
        guard !query.isEmpty else { return true }
        if rule.name.localizedCaseInsensitiveContains(query) {
            return true
        }
        return matchesRuleAmount(rule, query: query)
    }

    private func matchesRuleAmount(_ rule: BudgetRule, query: String) -> Bool {
        let formatted = MoneyFormatter.format(minorUnits: rule.amountMinorUnits, currency: currency)
        if formatted.localizedCaseInsensitiveContains(query) {
            return true
        }

        let majorUnits = MoneyFormatter.majorUnitsString(minorUnits: rule.amountMinorUnits, currency: currency)
        if majorUnits.localizedCaseInsensitiveContains(query) {
            return true
        }

        if let parsedMinor = MoneyFormatter.parseMajorUnits(query, currency: currency),
           parsedMinor == rule.amountMinorUnits {
            return true
        }

        return false
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
        BudgetRuleService.rules(in: .incoming, from: filteredRules)
    }

    private var outgoingRules: [BudgetRule] {
        BudgetRuleService.rules(in: .outgoing, from: filteredRules)
    }

    private var otherRules: [BudgetRule] {
        BudgetRuleService.rules(in: .other, from: filteredRules)
    }

    private var canReorder: Bool {
        trimmedSearchText.isEmpty && filterAccountId == nil
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
        .searchable(text: $searchText, prompt: "Search by name or amount")
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
                    reorderableRuleRows(incomingRules, move: moveIncomingRules)
                }
            }

            if !outgoingRules.isEmpty {
                Section("Outgoing") {
                    reorderableRuleRows(outgoingRules, move: moveOutgoingRules)
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
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 32)
    }

    @ViewBuilder
    private func reorderableRuleRows(
        _ groupRules: [BudgetRule],
        move: @escaping (IndexSet, Int) -> Void
    ) -> some View {
        if canReorder {
            ForEach(groupRules, id: \.id) { rule in
                ruleRow(rule)
            }
            .onMove(perform: move)
        } else {
            ForEach(groupRules, id: \.id) { rule in
                ruleRow(rule)
            }
        }
    }

    private func ruleRow(_ rule: BudgetRule) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(rule.name)
                    if BudgetRuleService.isExpiringSoon(rule), featureGate.isAvailable(.ruleExpiryWarnings) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Text(ruleMetadataSubtitle(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(ruleAmountLabel(rule))
                    .font(.body.weight(.medium).monospacedDigit())
                if rule.isArchived {
                    Text("Archived")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
        .tag(rule)
        .help(canReorder ? "Drag to reorder within this group" : "")
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

    private func ruleAmountLabel(_ rule: BudgetRule) -> String {
        let amount = MoneyFormatter.format(minorUnits: rule.amountMinorUnits, currency: currency)
        return "\(amount)\(rule.cycle.amountPeriodSuffix)"
    }

    private func ruleMetadataSubtitle(_ rule: BudgetRule) -> String {
        var parts = [rule.cycle.displayName]
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
            Menu {
                Button {
                    printBudgetRules()
                } label: {
                    Label("Print…", systemImage: "printer")
                }

                Button {
                    exportBudgetRulesPDF()
                } label: {
                    Label("Save as PDF…", systemImage: "doc.richtext")
                }

                Button {
                    exportBudgetRulesCSV()
                } label: {
                    Label("Save as CSV…", systemImage: "tablecells")
                }
            } label: {
                Label("Export", systemImage: "printer")
            }
            .disabled(!hasAnyRules || filteredRules.isEmpty)
            .help("Print or export budget rules")

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

    private func moveIncomingRules(from source: IndexSet, to destination: Int) {
        moveRules(in: incomingRules, from: source, to: destination)
    }

    private func moveOutgoingRules(from source: IndexSet, to destination: Int) {
        moveRules(in: outgoingRules, from: source, to: destination)
    }

    private func moveRules(in groupRules: [BudgetRule], from source: IndexSet, to destination: Int) {
        var ordered = groupRules
        ordered.move(fromOffsets: source, toOffset: destination)
        do {
            try BudgetRuleService.persistDisplayOrder(ordered, in: modelContext)
        } catch {
            print("Reorder rules failed: \(error)")
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

    private var exportFootnote: String? {
        var footnotes: [String] = []
        if showArchived {
            footnotes.append("Showing archived rules only.")
        }
        if let filterAccountId {
            footnotes.append("Filtered to \(BankAccountService.accountName(for: filterAccountId, accounts: accounts)).")
        }
        if !trimmedSearchText.isEmpty {
            footnotes.append("Filtered by search: \"\(trimmedSearchText)\".")
        }
        return footnotes.isEmpty ? nil : footnotes.joined(separator: " ")
    }

    private func budgetRulesPrintView() -> BudgetRulesPrintView {
        BudgetRulesPrintView(
            summary: summary,
            currency: currency,
            incoming: printableRows(for: incomingRules),
            outgoing: printableRows(for: outgoingRules),
            other: printableRows(for: otherRules),
            footnote: exportFootnote
        )
    }

    private func printBudgetRules() {
        PrintService.print(title: "Budget Rules") {
            budgetRulesPrintView()
        }
    }

    private func exportBudgetRulesPDF() {
        PrintService.exportPDF(title: "Budget Rules") {
            budgetRulesPrintView()
        }
    }

    private func exportBudgetRulesCSV() {
        let data = ExportService.budgetRulesCSVData(
            summary: summary,
            currency: currency,
            incoming: printableRows(for: incomingRules),
            outgoing: printableRows(for: outgoingRules),
            other: printableRows(for: otherRules),
            footnote: exportFootnote
        )
        ExportService.saveCSV(data: data, suggestedFilename: "Budget Rules.csv")
    }

    private func printableRows(for rules: [BudgetRule]) -> [PrintableBudgetRuleRow] {
        rules.map { rule in
            PrintableBudgetRuleRow(
                id: rule.id,
                name: rule.name,
                metadata: ruleMetadataSubtitle(rule),
                amount: ruleAmountLabel(rule),
                badge: rule.isArchived ? "Archived" : nil
            )
        }
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
