import SwiftUI
import SwiftData

struct HolidayActivityFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BudgetRuleSubCategory.sortOrder) private var allSubCategories: [BudgetRuleSubCategory]

    let currency: AppCurrency
    let holiday: Holiday
    var existingActivity: HolidayActivity?

    @State private var name = ""
    @State private var kind: HolidayActivityKind = .other
    @State private var amountText = ""
    @State private var notes = ""
    @State private var subCategory: BudgetRuleSubCategory?
    @State private var linkedAccountId: UUID?
    @State private var useCustomMonth = false
    @State private var plannedMonth = Calendar.current.component(.month, from: .now)
    @State private var plannedYear = Calendar.current.component(.year, from: .now)

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    Picker("Type", selection: $kind) {
                        ForEach(HolidayActivityKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    TextField("Name", text: $name)
                    TextField("Amount", text: $amountText)
                }

                Section("Category") {
                    BudgetRuleSubCategoryPicker(
                        selectedSubCategory: $subCategory,
                        orderGroup: .outgoing
                    )
                    AccountPicker(linkedAccountId: $linkedAccountId)
                }

                Section("Planned month") {
                    Toggle("Custom month", isOn: $useCustomMonth)
                    if useCustomMonth {
                        PlanningStartPicker(
                            month: $plannedMonth,
                            year: $plannedYear,
                            label: "Show in"
                        )
                    } else {
                        Text("Uses the trip default or start date month.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existingActivity == nil ? "Add Activity" : "Edit Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { loadExisting() }
        }
        .frame(minWidth: 420, minHeight: 480)
    }

    private func loadExisting() {
        guard let activity = existingActivity else { return }
        name = activity.name
        kind = activity.kind
        amountText = MoneyFormatter.majorUnitsString(minorUnits: activity.amountMinorUnits, currency: currency)
        notes = activity.notes
        subCategory = activity.subCategoryId.flatMap { id in
            allSubCategories.first { $0.id == id }
        }
        linkedAccountId = activity.linkedAccountId
        if activity.plannedYear > 0, activity.plannedMonth > 0 {
            useCustomMonth = true
            plannedYear = activity.plannedYear
            plannedMonth = activity.plannedMonth
        }
    }

    private func save() {
        let activity = existingActivity ?? HolidayActivity()
        if existingActivity == nil {
            activity.markCreated()
            activity.sortOrder = (holiday.activities.map(\.sortOrder).max() ?? -1) + 1
            activity.holiday = holiday
            modelContext.insert(activity)
        }

        activity.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        activity.kind = kind
        activity.amountMinorUnits = MoneyFormatter.parseMajorUnits(amountText, currency: currency) ?? 0
        activity.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        activity.subCategoryId = subCategory?.id
        activity.linkedAccountId = linkedAccountId
        if useCustomMonth {
            activity.plannedYear = plannedYear
            activity.plannedMonth = plannedMonth
        } else {
            activity.plannedYear = 0
            activity.plannedMonth = 0
        }
        activity.markUpdated()
        holiday.markUpdated()

        do {
            try modelContext.save()
            if holiday.status == .committed {
                let settings = try AppDataService.ensureSettings(in: modelContext)
                let months = try AppDataService.fetchMonths(settings: settings, in: modelContext)
                let tiles = try AppDataService.fetchAllTiles(in: modelContext)
                try HolidayService.syncCommittedHoliday(
                    holiday: holiday,
                    settings: settings,
                    months: months,
                    allTiles: tiles,
                    in: modelContext
                )
            }
            dismiss()
        } catch {
            print("Activity save failed: \(error)")
        }
    }
}
