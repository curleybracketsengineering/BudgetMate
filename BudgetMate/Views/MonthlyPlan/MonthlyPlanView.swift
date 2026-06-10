import SwiftUI
import SwiftData

struct MonthlyPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query(sort: [SortDescriptor(\BudgetMonth.year), SortDescriptor(\BudgetMonth.month)]) private var allMonths: [BudgetMonth]
    @Query private var allTiles: [BudgetTile]

    @Binding var selectedMonth: BudgetMonth?

    private var settings: AppSettings? { settingsList.first }

    private var orderedMonths: [BudgetMonth] {
        guard let settings else { return [] }
        let sequence = PlanningCalendar.monthSequence(
            startYear: settings.planningStartYear,
            startMonth: settings.planningStartMonth,
            count: settings.horizonMonths
        )
        let byKey = Dictionary(uniqueKeysWithValues: allMonths.map { ($0.monthKey, $0) })
        return sequence.compactMap { byKey["\($0.year)-\($0.month)"] }
    }

    var body: some View {
        Group {
            if let settings {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                        ForEach(orderedMonths, id: \.id) { month in
                            let tiles = CashFlowService.tilesForMonth(year: month.year, month: month.month, from: allTiles)
                            let totals = CashFlowService.totals(for: tiles)
                            Button {
                                selectedMonth = month
                            } label: {
                                MonthCardView(
                                    month: month,
                                    settings: settings,
                                    income: totals.income,
                                    expense: totals.expense,
                                    isSelected: selectedMonth?.id == month.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("No plan yet", systemImage: "calendar", description: Text("Complete setup in Settings."))
            }
        }
        .navigationTitle("Monthly Plan")
        .onAppear { ensureData() }
    }

    private func ensureData() {
        guard let settings else { return }
        do {
            _ = try AppDataService.ensureMonths(settings: settings, in: modelContext)
            try AppDataService.refreshForecast(in: modelContext)
        } catch {
            print("Monthly plan refresh failed: \(error)")
        }
    }
}
