import SwiftUI
import SwiftData

struct OneOffRuleFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let currency: AppCurrency
    let year: Int
    let month: Int
    var isMonthLocked: Bool = false

    @State private var name = ""
    @State private var amountText = ""
    @State private var type: BudgetType = .expense
    @State private var subCategory: BudgetRuleSubCategory?
    @State private var linkedAccountId: UUID?
    @State private var confidence: ConfidenceLevel = .estimated
    @State private var commitment: CommitmentType = .known

    private var monthTitle: String {
        BudgetMonth(year: year, month: month).displayTitle
    }

    var body: some View {
        NavigationStack {
            Form {
                if isMonthLocked {
                    Section {
                        Label("This month is locked. The tile may not be generated until the month is unlocked.", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Amount", text: $amountText)
                    Picker("Type", selection: $type) {
                        Text(BudgetType.expense.displayName).tag(BudgetType.expense)
                        Text(BudgetType.saving.displayName).tag(BudgetType.saving)
                    }
                    if let orderGroup = BudgetRuleService.OrderGroup.forPicker(from: type) {
                        BudgetRuleSubCategoryPicker(
                            selectedSubCategory: $subCategory,
                            orderGroup: orderGroup
                        )
                    }
                    AccountPicker(linkedAccountId: $linkedAccountId)
                }

                Section("Month") {
                    LabeledContent("Planned for", value: monthTitle)
                }

                Section("Metadata") {
                    Picker("Confidence", selection: $confidence) {
                        ForEach(ConfidenceLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    Picker("Commitment", selection: $commitment) {
                        ForEach(CommitmentType.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add One-off")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 420)
    }

    private func save() {
        let rule = BudgetRule()
        rule.markCreated()
        modelContext.insert(rule)

        var snapshot = BudgetRuleEditor.LoadedSnapshot(
            amountMinorUnits: 0,
            cycle: .oneOff,
            monthPatternRaw: "",
            startDate: PlanningCalendar.firstDayOfMonth(year: year, month: month)
        )

        BudgetRuleEditor.apply(
            to: rule,
            currency: currency,
            name: name,
            amountText: amountText,
            type: type,
            subCategory: subCategory,
            cycle: .oneOff,
            startDate: PlanningCalendar.firstDayOfMonth(year: year, month: month),
            hasEndDate: false,
            endDate: .now,
            isArchived: false,
            confidence: confidence,
            commitment: commitment,
            assumptionsNotes: "",
            selectedMonths: [],
            linkedAccountId: linkedAccountId,
            transferToAccountId: nil,
            showIndividuallyInPlan: true,
            snapshot: &snapshot
        )

        do {
            try BudgetRuleService.assignDisplayOrderForNewRule(rule, in: modelContext)
            try modelContext.save()
            try AppDataService.syncRuleTilesAndRefresh(rule: rule, in: modelContext)
            dismiss()
        } catch {
            print("One-off rule save failed: \(error)")
        }
    }
}
