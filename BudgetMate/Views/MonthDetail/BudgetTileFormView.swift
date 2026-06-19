import SwiftUI
import SwiftData

struct BudgetTileFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let currency: AppCurrency
    var existingTile: BudgetTile?
    var defaultYear: Int
    var defaultMonth: Int

    @State private var name = ""
    @State private var amountText = ""
    @State private var type: BudgetType = .expense
    @State private var subCategory: BudgetRuleSubCategory?
    @State private var year: Int
    @State private var month: Int
    @State private var status: BudgetTileStatus = .active
    @State private var confidence: ConfidenceLevel = .estimated
    @State private var commitment: CommitmentType = .known
    @State private var notes = ""
    @State private var linkedAccountId: UUID?
    @State private var transferToAccountId: UUID?

    init(currency: AppCurrency, existingTile: BudgetTile? = nil, defaultYear: Int, defaultMonth: Int) {
        self.currency = currency
        self.existingTile = existingTile
        self.defaultYear = defaultYear
        self.defaultMonth = defaultMonth
        _year = State(initialValue: existingTile?.year ?? defaultYear)
        _month = State(initialValue: existingTile?.month ?? defaultMonth)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Amount", text: $amountText)
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
                }

                Section("Month") {
                    Stepper("Year: \(year)", value: $year, in: 2020...2100)
                    Picker("Month", selection: $month) {
                        ForEach(1...12, id: \.self) { m in
                            Text(Calendar.current.monthSymbols[m - 1]).tag(m)
                        }
                    }
                }

                Section("Metadata") {
                    Picker("Status", selection: $status) {
                        ForEach(BudgetTileStatus.allCases) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
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
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existingTile == nil ? "Add Tile" : "Edit Tile")
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
        .frame(minWidth: 400, minHeight: 480)
    }

    private func loadExisting() {
        guard let tile = existingTile else { return }
        name = tile.name
        amountText = MoneyFormatter.majorUnitsString(minorUnits: tile.amountMinorUnits, currency: currency)
        type = tile.type
        subCategory = tile.subCategory
        year = tile.year
        month = tile.month
        status = tile.status
        confidence = tile.confidence
        commitment = tile.commitment
        notes = tile.notes
        linkedAccountId = tile.linkedAccountId
        transferToAccountId = tile.transferToAccountId
    }

    private func save() {
        let amount = MoneyFormatter.parseMajorUnits(amountText, currency: currency) ?? 0
        let tile: BudgetTile
        if let existingTile {
            tile = existingTile
        } else {
            tile = BudgetTile(year: year, month: month, name: name)
            tile.source = .manual
            tile.markCreated()
            modelContext.insert(tile)
        }

        tile.name = name
        tile.amountMinorUnits = amount
        tile.type = type
        tile.subCategory = BudgetRuleService.OrderGroup.forPicker(from: type) != nil ? subCategory : nil
        tile.year = year
        tile.month = month
        tile.status = status
        tile.confidence = confidence
        tile.commitment = commitment
        tile.notes = notes
        tile.linkedAccountId = linkedAccountId
        tile.transferToAccountId = type == .transfer ? transferToAccountId : nil
        tile.markUpdated()

        do {
            try AppDataService.refreshForecast(in: modelContext)
            dismiss()
        } catch {
            print("Tile save failed: \(error)")
        }
    }
}
