import SwiftUI
import SwiftData

struct MonthlyPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(FeatureGateService.self) private var featureGate
    @Query private var settingsList: [AppSettings]
    @Query(sort: [SortDescriptor(\BudgetMonth.year), SortDescriptor(\BudgetMonth.month)]) private var allMonths: [BudgetMonth]
    @Query private var allTiles: [BudgetTile]
    @Query private var rules: [BudgetRule]
    @Query(sort: \BankAccount.displayOrder) private var accounts: [BankAccount]

    @Binding var selectedMonth: BudgetMonth?

    private var settings: AppSettings? { settingsList.first }

    private var orderedMonths: [BudgetMonth] {
        guard let settings else { return [] }
        let sequence = PlanningCalendar.monthSequence(
            startYear: settings.planningStartYear,
            startMonth: settings.planningStartMonth,
            count: settings.horizonMonths
        )
        let byKey = allMonths.keyedByMonthKey()
        return sequence.compactMap { byKey["\($0.year)-\($0.month)"] }
    }

    private var hasActiveRules: Bool {
        rules.contains { $0.isActive && !$0.isArchived }
    }

    private var hasPlanActivity: Bool {
        allTiles.contains(where: \.isActive)
    }

    var body: some View {
        Group {
            if let settings {
                ScrollView {
                    VStack(spacing: 16) {
                        if hasActiveRules && !hasPlanActivity {
                            emptyPlanBanner
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                            ForEach(orderedMonths, id: \.id) { month in
                                let tiles = CashFlowService.tilesForMonth(year: month.year, month: month.month, from: allTiles)
                                let totals = CashFlowService.totals(for: tiles)
                                let accountBalances = CashFlowService.accountBalances(
                                    for: month,
                                    accounts: accounts,
                                    tiles: allTiles,
                                    settings: settings
                                )
                                Button {
                                    selectedMonth = month
                                } label: {
                                    MonthCardView(
                                        month: month,
                                        settings: settings,
                                        income: totals.income,
                                        expense: totals.expense,
                                        accounts: accounts,
                                        accountBalances: accountBalances,
                                        isSelected: selectedMonth?.id == month.id
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        planLengthFooter(settings)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("No plan yet", systemImage: "calendar", description: Text("Complete setup in Settings."))
            }
        }
        .navigationTitle("Monthly Plan")
        .onAppear { ensureData() }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    #if os(macOS)
                    Button {
                        printMonthlyPlan()
                    } label: {
                        Label("Print…", systemImage: "printer")
                    }
                    #endif

                    Button {
                        exportMonthlyPlanPDF()
                    } label: {
                        Label("Save as PDF…", systemImage: "doc.richtext")
                    }

                    Button {
                        exportMonthlyPlanCSV()
                    } label: {
                        Label("Save as CSV…", systemImage: "tablecells")
                    }
                } label: {
                    Label("Export", systemImage: "printer")
                }
                .disabled(orderedMonths.isEmpty)
                .help("Print or export the monthly plan")

                if let settings, featureGate.canExtendHorizon(currentMonths: settings.horizonMonths) {
                    Button {
                        extendPlan(byYears: 1, settings: settings)
                    } label: {
                        Label("Add year", systemImage: "plus.circle")
                    }
                    .help("Extend your plan by one year")
                }
            }
        }
    }

    @ViewBuilder
    private func planLengthFooter(_ settings: AppSettings) -> some View {
        VStack(spacing: 10) {
            Text("Planning \(PlanningHorizon.label(forMonths: settings.horizonMonths))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if featureGate.canExtendHorizon(currentMonths: settings.horizonMonths) {
                Button {
                    extendPlan(byYears: 1, settings: settings)
                } label: {
                    Label("Add year to plan", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
            } else if !featureGate.isProUnlocked {
                Label("Pro unlocks extra years beyond \(PlanningHorizon.baseYears)", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func extendPlan(byYears years: Int, settings: AppSettings) {
        do {
            try AppDataService.extendHorizon(
                byYears: years,
                settings: settings,
                maxMonths: featureGate.maxHorizonMonths(),
                in: modelContext
            )
        } catch {
            print("Extend plan failed: \(error)")
        }
    }

    private var emptyPlanBanner: some View {
        let periodLabel = settings.flatMap { BudgetRuleService.PlanningPeriod.from(settings: $0)?.label }

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("No tiles in your plan yet")
                    .font(.subheadline.weight(.semibold))
                if let periodLabel {
                    Text("Your planning period is \(periodLabel) (Settings). Tiles are created from each rule's start date, and stop at its end date if set. Check those dates in Budget Rules, then tap Generate Tiles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Go to Budget Rules and tap Generate Tiles, or save a rule to fill your monthly plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func ensureData() {
        guard let settings else { return }
        let normalized = featureGate.normalizedHorizon(settings.horizonMonths)
        if normalized != settings.horizonMonths {
            settings.horizonMonths = normalized
            settings.markUpdated()
        }
        do {
            _ = try AppDataService.ensureMonths(settings: settings, in: modelContext)
            try AppDataService.refreshForecast(in: modelContext)
        } catch {
            print("Monthly plan refresh failed: \(error)")
        }
    }

    private var printableMonthRows: [PrintableMonthRow] {
        orderedMonths.map { month in
            let tiles = CashFlowService.tilesForMonth(year: month.year, month: month.month, from: allTiles)
            let totals = CashFlowService.totals(for: tiles)
            return PrintableMonthRow(
                id: month.id,
                title: month.displayTitle,
                opening: month.openingBalanceMinorUnits,
                income: totals.income,
                expense: totals.expense,
                closing: month.closingBalanceMinorUnits,
                isLocked: month.isLocked
            )
        }
    }

    private func monthlyPlanPrintView(for settings: AppSettings) -> MonthlyPlanPrintView {
        MonthlyPlanPrintView(
            currency: settings.currency,
            months: printableMonthRows,
            horizonLabel: PlanningHorizon.label(forMonths: settings.horizonMonths)
        )
    }

    private func printMonthlyPlan() {
        guard let settings else { return }
        PrintService.print(title: "Monthly Plan") {
            monthlyPlanPrintView(for: settings)
        }
    }

    private func exportMonthlyPlanPDF() {
        guard let settings else { return }
        PrintService.exportPDF(title: "Monthly Plan") {
            monthlyPlanPrintView(for: settings)
        }
    }

    private func exportMonthlyPlanCSV() {
        guard let settings else { return }
        let data = ExportService.csvData(rows: printableMonthRows, currency: settings.currency)
        ExportService.saveCSV(data: data, suggestedFilename: "Monthly Plan.csv")
    }
}
