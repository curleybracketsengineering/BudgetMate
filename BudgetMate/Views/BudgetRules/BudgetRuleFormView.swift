import SwiftUI
import SwiftData

struct BudgetRuleFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let currency: AppCurrency
    var existingRule: BudgetRule?
    var template: BudgetRuleStarterTemplate?
    var prefilledSubCategory: BudgetRuleSubCategory?

    @State private var name = ""
    @State private var amountText = ""
    @State private var type: BudgetType = .expense
    @State private var subCategory: BudgetRuleSubCategory?
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

    var body: some View {
        NavigationStack {
            Form {
                BudgetRuleEditorFields(
                    name: $name,
                    amountText: $amountText,
                    type: $type,
                    subCategory: $subCategory,
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
                    showIndividuallyInPlan: $showIndividuallyInPlan
                )
            }
            .formStyle(.grouped)
            .navigationTitle(existingRule == nil ? "New Rule" : "Edit Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear { loadExisting() }
            .onChange(of: type) { _, newType in
                if newType != .transfer {
                    transferToAccountId = nil
                }
                if BudgetRuleService.OrderGroup.forPicker(from: newType) == nil {
                    subCategory = nil
                } else if let subCategory, subCategory.orderGroup != BudgetRuleService.OrderGroup.forType(newType) {
                    self.subCategory = nil
                }
            }
        }
        .frame(minWidth: 420, minHeight: 520)
    }

    private func loadExisting() {
        if let rule = existingRule {
            let loaded = BudgetRuleEditor.load(from: rule, currency: currency)
            name = loaded.name
            amountText = loaded.amountText
            type = loaded.type
            subCategory = loaded.subCategory
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
            return
        }

        if let template {
            name = template.name
            type = template.type
            if let orderGroup = BudgetRuleService.OrderGroup.forPicker(from: template.type),
               !template.defaultSubCategoryTitle.isEmpty {
                subCategory = BudgetRuleSubCategoryService.findOrCreate(
                    orderGroup: orderGroup,
                    title: template.defaultSubCategoryTitle,
                    in: modelContext
                )
            }
            cycle = template.cycle
            commitment = template.commitment
            confidence = template.confidence
            selectedMonths = BudgetRuleService.parseMonthPattern(template.monthPatternRaw)
            return
        }

        guard let prefilledSubCategory else { return }
        subCategory = prefilledSubCategory
        switch prefilledSubCategory.orderGroup {
        case .incoming:
            type = .income
        case .outgoing:
            type = .expense
        case .other:
            break
        }
    }

    private func save() {
        let rule: BudgetRule
        if let existingRule {
            rule = existingRule
        } else {
            rule = BudgetRule()
            rule.markCreated()
            modelContext.insert(rule)
        }

        BudgetRuleEditor.apply(
            to: rule,
            currency: currency,
            name: name,
            amountText: amountText,
            type: type,
            subCategory: subCategory,
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
            if existingRule == nil {
                try BudgetRuleService.assignDisplayOrderForNewRule(rule, in: modelContext)
            }
            try modelContext.save()
            _ = try AppDataService.generateAndRefresh(in: modelContext)
            dismiss()
        } catch {
            print("Rule save failed: \(error)")
        }
    }
}
