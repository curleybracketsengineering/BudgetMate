import SwiftUI
import SwiftData

struct BudgetRuleEditorFields: View {
    @Query private var settingsList: [AppSettings]

    @Binding var name: String
    @Binding var amountText: String
    @Binding var type: BudgetType
    @Binding var subCategory: BudgetRuleSubCategory?
    @Binding var cycle: BudgetCycleType
    @Binding var startDate: Date
    @Binding var hasEndDate: Bool
    @Binding var endDate: Date
    @Binding var isArchived: Bool
    @Binding var confidence: ConfidenceLevel
    @Binding var commitment: CommitmentType
    @Binding var assumptionsNotes: String
    @Binding var selectedMonths: Set<Int>
    @Binding var linkedAccountId: UUID?
    @Binding var transferToAccountId: UUID?
    @Binding var showIndividuallyInPlan: Bool

    var amountFieldFocused: FocusState<Bool>.Binding?
    var onAmountCommit: (() -> Void)?

    var body: some View {
        Section("Rule") {
            TextField("Name", text: $name)
            if let amountFieldFocused {
                TextField("Amount", text: $amountText)
                    .focused(amountFieldFocused)
                    .onSubmit { onAmountCommit?() }
            } else {
                TextField("Amount", text: $amountText)
            }
            Picker("Type", selection: $type) {
                ForEach(BudgetType.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            if let orderGroup = BudgetRuleService.OrderGroup.forPicker(from: type) {
                BudgetRuleSubCategoryPicker(
                    selectedSubCategory: $subCategory,
                    orderGroup: orderGroup
                )
            }
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

        if cycle == .tenMonthly || cycle == .custom {
            Section("Active months") {
                Text(
                    cycle == .tenMonthly
                        ? "Select the months this payment occurs (typically 10 per year)."
                        : "Select which months this payment occurs."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                MonthPatternPicker(selectedMonths: $selectedMonths)
            }
        }

        if cycle == .everyFourWeeks {
            FourWeeklyCycleStartSection(startDate: $startDate, settings: settings)
        }

        Section("Dates") {
            if cycle != .everyFourWeeks {
                DatePicker("Start date", selection: $startDate, displayedComponents: .date)
            }
            if let startOverlapMessage {
                Text(startOverlapMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Has end date", isOn: $hasEndDate)
            if hasEndDate {
                DatePicker("End date", selection: $endDate, displayedComponents: .date)
                Text("Tiles are not generated after this month.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let endOverlapMessage {
                    Text(endOverlapMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onChange(of: hasEndDate) { _, enabled in
            if enabled, endDate < startDate {
                endDate = startDate
            }
        }

        Section("Plan display") {
            Toggle("Show individually in plan", isOn: $showIndividuallyInPlan)
            Text("When off, this rule rolls up into the Income or Outgoings total for each month. Four-weekly income is grouped separately from monthly income.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var settings: AppSettings? { settingsList.first }

    private var startOverlapMessage: String? {
        guard let settings else { return nil }
        let draft = draftRule()
        guard case .startsAfterPlan(_, let planLabel) = BudgetRuleService.planningOverlap(for: draft, settings: settings) else {
            return nil
        }
        return "This rule starts after your planning period (\(planLabel)). Tiles appear from the start date onward."
    }

    private var endOverlapMessage: String? {
        guard hasEndDate, let settings else { return nil }
        let draft = draftRule()
        guard case .endsBeforePlan(let endLabel, let planLabel) = BudgetRuleService.planningOverlap(for: draft, settings: settings) else {
            return nil
        }
        return "End date (\(endLabel)) is before your planning period (\(planLabel)). No tiles will be generated."
    }

    private func draftRule() -> BudgetRule {
        let rule = BudgetRule()
        rule.startDate = startDate
        rule.endDate = hasEndDate ? endDate : nil
        return rule
    }
}

struct FourWeeklyCycleStartSection: View {
    @Binding var startDate: Date
    let settings: AppSettings?

    private var cycleMonth: Binding<Int> {
        Binding(
            get: { CycleStartDate.components(from: startDate).month },
            set: { newMonth in
                let parts = CycleStartDate.components(from: startDate)
                startDate = CycleStartDate.makeDate(year: parts.year, month: newMonth, day: parts.day)
            }
        )
    }

    private var cycleYear: Binding<Int> {
        Binding(
            get: { CycleStartDate.components(from: startDate).year },
            set: { newYear in
                let parts = CycleStartDate.components(from: startDate)
                startDate = CycleStartDate.makeDate(year: newYear, month: parts.month, day: parts.day)
            }
        )
    }

    private var cycleDay: Binding<Int> {
        Binding(
            get: { CycleStartDate.components(from: startDate).day },
            set: { newDay in
                let parts = CycleStartDate.components(from: startDate)
                startDate = CycleStartDate.makeDate(year: parts.year, month: parts.month, day: newDay)
            }
        )
    }

    var body: some View {
        Section("Cycle start") {
            Text("Every 4 weeks gives 13 payments per year. Set your first payment date — the cycle is calculated from there, but tiles only appear from your planning start month onward.")
                .font(.caption)
                .foregroundStyle(.secondary)

            PlanningStartPicker(month: cycleMonth, year: cycleYear, label: "First payment")

            Picker("Day of month", selection: cycleDay) {
                ForEach(1...31, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }

            if let settings {
                let draft = draftRule()
                let months = BudgetGenerationService.scheduledMonthLabels(for: draft, settings: settings)
                if !months.isEmpty {
                    Text("Payments land in: \(months.joined(separator: ", ")). Thirteen payments per year in total.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func draftRule() -> BudgetRule {
        let rule = BudgetRule()
        rule.cycle = .everyFourWeeks
        rule.startDate = startDate
        return rule
    }
}

private enum CycleStartDate {
    static func components(from date: Date) -> (year: Int, month: Int, day: Int) {
        let calendar = Calendar.current
        return (
            calendar.component(.year, from: date),
            calendar.component(.month, from: date),
            calendar.component(.day, from: date)
        )
    }

    static func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else {
            return Date()
        }
        components.day = min(max(1, day), range.count)
        return calendar.date(from: components) ?? Date()
    }
}

struct MonthPatternPicker: View {
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

enum BudgetRuleEditor {
    struct LoadedSnapshot {
        var amountMinorUnits: Int
        var cycle: BudgetCycleType
        var monthPatternRaw: String
        var startDate: Date
    }

    static func load(from rule: BudgetRule, currency: AppCurrency) -> (
        name: String,
        amountText: String,
        type: BudgetType,
        subCategory: BudgetRuleSubCategory?,
        cycle: BudgetCycleType,
        startDate: Date,
        hasEndDate: Bool,
        endDate: Date,
        isArchived: Bool,
        confidence: ConfidenceLevel,
        commitment: CommitmentType,
        assumptionsNotes: String,
        selectedMonths: Set<Int>,
        linkedAccountId: UUID?,
        transferToAccountId: UUID?,
        showIndividuallyInPlan: Bool,
        snapshot: LoadedSnapshot
    ) {
        (
            rule.name,
            MoneyFormatter.majorUnitsString(minorUnits: rule.amountMinorUnits, currency: currency),
            rule.type,
            rule.subCategory,
            rule.cycle,
            rule.startDate,
            rule.endDate != nil,
            rule.endDate ?? .now,
            rule.isArchived,
            rule.confidence,
            rule.commitment,
            rule.assumptionsNotes,
            BudgetRuleService.parseMonthPattern(rule.monthPatternRaw),
            rule.linkedAccountId,
            rule.transferToAccountId,
            rule.showIndividuallyInPlan,
            LoadedSnapshot(
                amountMinorUnits: rule.amountMinorUnits,
                cycle: rule.cycle,
                monthPatternRaw: rule.monthPatternRaw,
                startDate: rule.startDate
            )
        )
    }

    @discardableResult
    static func apply(
        to rule: BudgetRule,
        currency: AppCurrency,
        name: String,
        amountText: String,
        type: BudgetType,
        subCategory: BudgetRuleSubCategory?,
        cycle: BudgetCycleType,
        startDate: Date,
        hasEndDate: Bool,
        endDate: Date,
        isArchived: Bool,
        confidence: ConfidenceLevel,
        commitment: CommitmentType,
        assumptionsNotes: String,
        selectedMonths: Set<Int>,
        linkedAccountId: UUID?,
        transferToAccountId: UUID?,
        showIndividuallyInPlan: Bool,
        snapshot: inout LoadedSnapshot
    ) -> LoadedSnapshot {
        let amount = MoneyFormatter.parseMajorUnits(amountText, currency: currency) ?? 0
        let monthPatternRaw = (cycle == .tenMonthly || cycle == .custom)
            ? BudgetRuleService.formatMonthPattern(selectedMonths)
            : ""

        rule.name = name
        rule.amountMinorUnits = amount
        rule.type = type
        if BudgetRuleService.OrderGroup.forPicker(from: type) != nil {
            if let subCategory, subCategory.orderGroup == BudgetRuleService.OrderGroup.forType(type) {
                rule.subCategory = subCategory
            } else {
                rule.subCategory = nil
            }
        } else {
            rule.subCategory = nil
        }
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
        rule.showIndividuallyInPlan = showIndividuallyInPlan
        rule.monthPatternRaw = monthPatternRaw

        let amountChanged = amount != snapshot.amountMinorUnits
        let scheduleChanged = cycle != snapshot.cycle
            || monthPatternRaw != snapshot.monthPatternRaw
            || startDate != snapshot.startDate
        if amountChanged || scheduleChanged {
            rule.monthlyEquivalentMinorUnits = BudgetRuleService.calculatedMonthlyEquivalent(for: rule)
        }

        rule.markUpdated()

        snapshot = LoadedSnapshot(
            amountMinorUnits: amount,
            cycle: cycle,
            monthPatternRaw: monthPatternRaw,
            startDate: startDate
        )
        return snapshot
    }
}
