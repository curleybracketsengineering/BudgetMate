import SwiftUI
import SwiftData

struct BudgetRuleFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let currency: AppCurrency
    var existingRule: BudgetRule?
    var template: BudgetRuleStarterTemplate?

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Rule") {
                    TextField("Name", text: $name)
                    TextField("Amount", text: $amountText)
                    Picker("Type", selection: $type) {
                        ForEach(BudgetType.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    TextField("Category", text: $category)
                    if type == .transfer {
                        TransferAccountFields(
                            fromAccountId: $linkedAccountId,
                            toAccountId: $transferToAccountId
                        )
                    } else {
                        AccountPicker(linkedAccountId: $linkedAccountId)
                    }
                    Picker("Cycle", selection: $cycle) {
                        ForEach(BudgetCycleType.allCases) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                }

                if cycle == .tenMonthly {
                    Section("Active months") {
                        Text("Select the months this payment occurs (typically 10 per year).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        MonthPatternPicker(selectedMonths: $selectedMonths)
                    }
                }

                Section("Dates") {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    Toggle("Has end date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("End date", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section("Metadata") {
                    Toggle("Archived", isOn: $isArchived)
                    Picker("Confidence", selection: $confidence) {
                        ForEach(ConfidenceLevel.allCases) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    Picker("Commitment", selection: $commitment) {
                        ForEach(CommitmentType.allCases) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    TextField("Assumptions / notes", text: $assumptionsNotes, axis: .vertical)
                        .lineLimit(3...6)
                }
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
            }
        }
        .frame(minWidth: 420, minHeight: 520)
    }

    private func loadExisting() {
        if let rule = existingRule {
            name = rule.name
            amountText = MoneyFormatter.majorUnitsString(minorUnits: rule.amountMinorUnits, currency: currency)
            type = rule.type
            category = rule.category
            cycle = rule.cycle
            startDate = rule.startDate
            hasEndDate = rule.endDate != nil
            endDate = rule.endDate ?? .now
            isArchived = rule.isArchived
            confidence = rule.confidence
            commitment = rule.commitment
            assumptionsNotes = rule.assumptionsNotes
            selectedMonths = BudgetRuleService.parseMonthPattern(rule.monthPatternRaw)
            linkedAccountId = rule.linkedAccountId
            transferToAccountId = rule.transferToAccountId
            return
        }

        guard let template else { return }
        name = template.name
        type = template.type
        category = template.category
        cycle = template.cycle
        commitment = template.commitment
        confidence = template.confidence
        selectedMonths = BudgetRuleService.parseMonthPattern(template.monthPatternRaw)
    }

    private func save() {
        let amount = MoneyFormatter.parseMajorUnits(amountText, currency: currency) ?? 0
        let rule: BudgetRule
        if let existingRule {
            rule = existingRule
        } else {
            rule = BudgetRule()
            rule.markCreated()
            modelContext.insert(rule)
        }

        rule.name = name
        rule.amountMinorUnits = amount
        rule.type = type
        rule.category = category
        rule.cycle = cycle
        rule.startDate = startDate
        rule.endDate = hasEndDate ? endDate : nil
        rule.isArchived = isArchived
        rule.isActive = !isArchived
        rule.confidence = confidence
        rule.commitment = commitment
        rule.assumptionsNotes = assumptionsNotes
        rule.linkedAccountId = linkedAccountId
        rule.transferToAccountId = type == .transfer ? transferToAccountId : nil
        rule.monthPatternRaw = cycle == .tenMonthly
            ? BudgetRuleService.formatMonthPattern(selectedMonths)
            : ""
        rule.markUpdated()

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Rule save failed: \(error)")
        }
    }
}

private struct MonthPatternPicker: View {
    @Binding var selectedMonths: Set<Int>

    private let monthSymbols = Calendar.current.shortMonthSymbols

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 8) {
            ForEach(1...12, id: \.self) { month in
                let isSelected = selectedMonths.contains(month)
                Button {
                    if isSelected {
                        selectedMonths.remove(month)
                    } else {
                        selectedMonths.insert(month)
                    }
                } label: {
                    Text(monthSymbols[month - 1])
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)
            }
        }

        if !selectedMonths.isEmpty {
            Text("\(selectedMonths.count) month\(selectedMonths.count == 1 ? "" : "s") selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
