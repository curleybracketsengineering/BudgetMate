import SwiftUI
import SwiftData

struct BudgetRuleDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(FeatureGateService.self) private var featureGate
    @Query private var settingsList: [AppSettings]
    @Query private var tiles: [BudgetTile]
    @Query(sort: \BankAccount.displayOrder) private var accounts: [BankAccount]

    let rule: BudgetRule
    var onDeleted: (() -> Void)?

    @State private var name = ""
    @State private var amountText = ""
    @State private var type: BudgetType = .expense
    @State private var category = ""
    @State private var cycle: BudgetCycleType = .monthly
    @State private var startDate = Date.now
    @State private var hasEndDate = false
    @State private var endDate = Date.now
    @State private var isArchived = false
    @State private var confidence: ConfidenceLevel = .estimated
    @State private var commitment: CommitmentType = .known
    @State private var assumptionsNotes = ""
    @State private var selectedMonths: Set<Int> = []
    @State private var linkedAccountId: UUID?
    @State private var transferToAccountId: UUID?
    @State private var showIndividuallyInPlan = false
    @State private var loadedSnapshot = BudgetRuleEditor.LoadedSnapshot(
        amountMinorUnits: 0,
        cycle: .monthly,
        monthPatternRaw: "",
        startDate: .now
    )
    @State private var didLoad = false
    @State private var rulePendingDeletion: BudgetRule?

    @FocusState private var amountFieldFocused: Bool

    private var currency: AppCurrency { settingsList.first?.currency ?? .GBP }

    private var monthlyEquivalent: Int {
        BudgetRuleService.monthlyEquivalent(for: rule)
    }

    private var linkedTileCount: Int {
        tiles.filter { $0.linkedRuleId == rule.id && $0.isActive }.count
    }

    var body: some View {
        formContent
            .modifier(autoSaveModifier)
            .confirmationDialog(
                "Delete this rule permanently?",
                isPresented: deleteDialogPresented,
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
    }

    private var formContent: some View {
        Form {
            if showExpiryWarning, let endDate = rule.endDate {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Ends \(endDate.formatted(date: .abbreviated, time: .omitted))")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                }
            }

            Section {
                LabeledContent("Status") {
                    statusLabel
                }
                LabeledContent("Per month") {
                    Text(MoneyFormatter.format(minorUnits: monthlyEquivalent, currency: currency))
                        .foregroundStyle(type == .income ? .green : .primary)
                }
                if linkedTileCount > 0 {
                    LabeledContent("Tiles") {
                        Text("\(linkedTileCount) in plan")
                    }
                }
            }

            BudgetRuleEditorFields(
                name: $name,
                amountText: $amountText,
                type: $type,
                category: $category,
                cycle: $cycle,
                startDate: $startDate,
                hasEndDate: $hasEndDate,
                endDate: $endDate,
                isArchived: $isArchived,
                confidence: $confidence,
                commitment: $commitment,
                assumptionsNotes: $assumptionsNotes,
                selectedMonths: $selectedMonths,
                linkedAccountId: $linkedAccountId,
                transferToAccountId: $transferToAccountId,
                showIndividuallyInPlan: $showIndividuallyInPlan,
                amountFieldFocused: $amountFieldFocused
            )

            if rule.isArchived {
                Section {
                    Button {
                        restore()
                    } label: {
                        Label("Restore from archive", systemImage: "arrow.uturn.backward")
                    }
                    Button(role: .destructive) {
                        rulePendingDeletion = rule
                    } label: {
                        Label("Delete permanently", systemImage: "trash")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(name.isEmpty ? "Rule" : name)
        .onAppear { loadFromRule() }
        .onChange(of: rule.id) { loadFromRule() }
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { rulePendingDeletion != nil },
            set: { if !$0 { rulePendingDeletion = nil } }
        )
    }

    private var autoSaveModifier: BudgetRuleDetailAutoSaveModifier {
        BudgetRuleDetailAutoSaveModifier(
            type: $type,
            cycle: $cycle,
            startDate: $startDate,
            hasEndDate: $hasEndDate,
            endDate: $endDate,
            isArchived: $isArchived,
            confidence: $confidence,
            commitment: $commitment,
            selectedMonths: $selectedMonths,
            linkedAccountId: $linkedAccountId,
            transferToAccountId: $transferToAccountId,
            showIndividuallyInPlan: $showIndividuallyInPlan,
            name: $name,
            category: $category,
            assumptionsNotes: $assumptionsNotes,
            amountFieldFocused: $amountFieldFocused,
            onSave: saveIfReady,
            onClearTransferAccount: { transferToAccountId = nil }
        )
    }

    private var showExpiryWarning: Bool {
        BudgetRuleService.isExpiringSoon(rule) && featureGate.isAvailable(.ruleExpiryWarnings)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if rule.isArchived {
            statusBadge("Archived", color: .secondary)
        } else if !rule.isActive {
            statusBadge("Paused", color: .orange)
        } else {
            statusBadge("Active", color: .green)
        }
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func loadFromRule() {
        didLoad = false
        let loaded = BudgetRuleEditor.load(from: rule, currency: currency)
        name = loaded.name
        amountText = loaded.amountText
        type = loaded.type
        category = loaded.category
        cycle = loaded.cycle
        startDate = loaded.startDate
        hasEndDate = loaded.hasEndDate
        endDate = loaded.endDate
        isArchived = loaded.isArchived
        confidence = loaded.confidence
        commitment = loaded.commitment
        assumptionsNotes = loaded.assumptionsNotes
        selectedMonths = loaded.selectedMonths
        linkedAccountId = loaded.linkedAccountId
        transferToAccountId = loaded.transferToAccountId
        showIndividuallyInPlan = loaded.showIndividuallyInPlan
        loadedSnapshot = loaded.snapshot
        didLoad = true
    }

    private func saveIfReady() {
        guard didLoad else { return }
        BudgetRuleEditor.apply(
            to: rule,
            currency: currency,
            name: name,
            amountText: amountText,
            type: type,
            category: category,
            cycle: cycle,
            startDate: startDate,
            hasEndDate: hasEndDate,
            endDate: endDate,
            isArchived: isArchived,
            confidence: confidence,
            commitment: commitment,
            assumptionsNotes: assumptionsNotes,
            selectedMonths: selectedMonths,
            linkedAccountId: linkedAccountId,
            transferToAccountId: transferToAccountId,
            showIndividuallyInPlan: showIndividuallyInPlan,
            snapshot: &loadedSnapshot
        )
        do {
            try modelContext.save()
            try AppDataService.syncRuleTilesAndRefresh(rule: rule, in: modelContext)
        } catch {
            print("Rule save failed: \(error)")
        }
    }

    private func restore() {
        isArchived = false
        saveIfReady()
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
            rulePendingDeletion = nil
            onDeleted?()
            try AppDataService.refreshForecast(in: modelContext)
        } catch {
            print("Delete rule failed: \(error)")
        }
    }
}

private struct BudgetRuleDetailAutoSaveModifier: ViewModifier {
    @Binding var type: BudgetType
    @Binding var cycle: BudgetCycleType
    @Binding var startDate: Date
    @Binding var hasEndDate: Bool
    @Binding var endDate: Date
    @Binding var isArchived: Bool
    @Binding var confidence: ConfidenceLevel
    @Binding var commitment: CommitmentType
    @Binding var selectedMonths: Set<Int>
    @Binding var linkedAccountId: UUID?
    @Binding var transferToAccountId: UUID?
    @Binding var showIndividuallyInPlan: Bool
    @Binding var name: String
    @Binding var category: String
    @Binding var assumptionsNotes: String
    var amountFieldFocused: FocusState<Bool>.Binding

    let onSave: () -> Void
    let onClearTransferAccount: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: type) { _, newType in
                if newType != .transfer {
                    onClearTransferAccount()
                }
                onSave()
            }
            .onChange(of: cycle) { onSave() }
            .onChange(of: startDate) { onSave() }
            .onChange(of: hasEndDate) { onSave() }
            .onChange(of: endDate) { onSave() }
            .onChange(of: isArchived) { onSave() }
            .onChange(of: confidence) { onSave() }
            .onChange(of: commitment) { onSave() }
            .onChange(of: selectedMonths) { onSave() }
            .onChange(of: linkedAccountId) { onSave() }
            .onChange(of: transferToAccountId) { onSave() }
            .onChange(of: showIndividuallyInPlan) { onSave() }
            .onChange(of: name) { onSave() }
            .onChange(of: category) { onSave() }
            .onChange(of: assumptionsNotes) { onSave() }
            .onChange(of: amountFieldFocused.wrappedValue) { previous, _ in
                if previous == true {
                    onSave()
                }
            }
    }
}
