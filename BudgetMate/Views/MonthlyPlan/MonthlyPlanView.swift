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
                    Section("Monthly") {
                        #if os(macOS)
                        Menu {
                            ForEach(MonthlyPlanExportRange.allCases) { range in
                                Button {
                                    printMonthlyPlan(range: range)
                                } label: {
                                    Text(range.label)
                                }
                            }
                        } label: {
                            Label("Print…", systemImage: "printer")
                        }
                        #endif

                        Menu {
                            ForEach(MonthlyPlanExportRange.allCases) { range in
                                Button {
                                    exportMonthlyPlanPDF(range: range)
                                } label: {
                                    Text(range.label)
                                }
                            }
                        } label: {
                            Label("Save as PDF…", systemImage: "doc.richtext")
                        }

                        Menu {
                            ForEach(MonthlyPlanExportRange.allCases) { range in
                                Button {
                                    exportMonthlyPlanCSV(range: range)
                                } label: {
                                    Text(range.label)
                                }
                            }
                        } label: {
                            Label("Save as CSV…", systemImage: "tablecells")
                        }
                    }
                    .disabled(orderedMonths.isEmpty)

                    Section("By month") {
                        #if os(macOS)
                        Menu {
                            ForEach(MonthlyPlanExportRange.allCases) { range in
                                Button {
                                    printMonthDetail(range: range)
                                } label: {
                                    Text(range.label)
                                }
                            }
                        } label: {
                            Label("Print…", systemImage: "printer")
                        }
                        #endif

                        Menu {
                            ForEach(MonthlyPlanExportRange.allCases) { range in
                                Button {
                                    exportMonthDetailPDF(range: range)
                                } label: {
                                    Text(range.label)
                                }
                            }
                        } label: {
                            Label("Save as PDF…", systemImage: "doc.richtext")
                        }

                        Menu {
                            ForEach(MonthlyPlanExportRange.allCases) { range in
                                Button {
                                    exportMonthDetailCSV(range: range)
                                } label: {
                                    Text(range.label)
                                }
                            }
                        } label: {
                            Label("Save as CSV…", systemImage: "tablecells")
                        }
                    }
                    .disabled(orderedMonths.isEmpty)
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
        guard let settings else { return [] }
        let hasMultipleAccounts = accounts.count > 1

        return orderedMonths.map { month in
            let tiles = CashFlowService.tilesForMonth(year: month.year, month: month.month, from: allTiles)
            let totals = CashFlowService.totals(for: tiles)
            let accountBalances = CashFlowService.accountBalances(
                for: month,
                accounts: accounts,
                tiles: allTiles,
                settings: settings
            )
            let accountOpenings: [PrintableAccountOpening] = hasMultipleAccounts
                ? accounts.compactMap { account in
                    guard let balance = accountBalances.first(where: { $0.accountId == account.id }) else {
                        return nil
                    }
                    return PrintableAccountOpening(
                        id: account.id,
                        name: account.name,
                        openingMinorUnits: balance.openingBalanceMinorUnits
                    )
                }
                : []

            return PrintableMonthRow(
                id: month.id,
                title: month.displayTitle,
                opening: month.openingBalanceMinorUnits,
                income: totals.income,
                expense: totals.expense,
                closing: month.closingBalanceMinorUnits,
                isLocked: month.isLocked,
                accountOpenings: accountOpenings
            )
        }
    }

    private func printMonthlyPlan(range: MonthlyPlanExportRange) {
        guard let settings else { return }
        let rows = printableMonthRows
        let months = range.selectedMonths(from: rows)
        guard !months.isEmpty else { return }
        let pages = MonthlyPlanPrintDocument.pageViews(
            currency: settings.currency,
            settings: settings,
            months: months,
            horizonLabel: range.horizonLabel(
                from: rows,
                fullHorizonLabel: PlanningHorizon.label(forMonths: settings.horizonMonths)
            )
        )
        PrintService.printPaginated(title: "Monthly Plan", orientation: .landscape, pages: pages)
    }

    private func exportMonthlyPlanPDF(range: MonthlyPlanExportRange) {
        guard let settings else { return }
        let rows = printableMonthRows
        let months = range.selectedMonths(from: rows)
        guard !months.isEmpty else { return }
        let pages = MonthlyPlanPrintDocument.pageViews(
            currency: settings.currency,
            settings: settings,
            months: months,
            horizonLabel: range.horizonLabel(
                from: rows,
                fullHorizonLabel: PlanningHorizon.label(forMonths: settings.horizonMonths)
            )
        )
        PrintService.exportPaginatedPDF(title: "Monthly Plan", orientation: .landscape, pages: pages)
    }

    private func exportMonthlyPlanCSV(range: MonthlyPlanExportRange) {
        guard let settings else { return }
        let rows = printableMonthRows
        let months = range.selectedMonths(from: rows)
        guard !months.isEmpty else { return }
        let data = ExportService.csvData(rows: months, currency: settings.currency)
        ExportService.saveCSV(data: data, suggestedFilename: "Monthly Plan.csv")
    }

    private func selectedPlanMonths(for range: MonthlyPlanExportRange) -> [BudgetMonth] {
        range.selectedItems(from: orderedMonths)
    }

    private func printableMonthDetails(for months: [BudgetMonth]) -> [PrintableMonthDetail] {
        guard let settings else { return [] }
        return months.map { month in
            MonthDetailPrintDocument.build(
                month: month,
                tiles: allTiles,
                rules: rules,
                accounts: accounts,
                settings: settings
            )
        }
    }

    private func monthDetailExportTitle(range: MonthlyPlanExportRange) -> String {
        guard let settings else { return "Monthly Detail" }
        let label = range.horizonLabel(
            from: printableMonthRows,
            fullHorizonLabel: PlanningHorizon.label(forMonths: settings.horizonMonths)
        )
        return "\(label) Detail"
    }

    private func monthDetailPages(currency: AppCurrency, details: [PrintableMonthDetail]) -> [CurrentMonthDetailPrintView] {
        details.map { CurrentMonthDetailPrintView(currency: currency, detail: $0) }
    }

    private func printMonthDetail(range: MonthlyPlanExportRange) {
        guard let settings else { return }
        let months = selectedPlanMonths(for: range)
        let details = printableMonthDetails(for: months)
        guard !details.isEmpty else { return }
        PrintService.printPaginated(
            title: monthDetailExportTitle(range: range),
            orientation: .landscape,
            pages: monthDetailPages(currency: settings.currency, details: details)
        )
    }

    private func exportMonthDetailPDF(range: MonthlyPlanExportRange) {
        guard let settings else { return }
        let months = selectedPlanMonths(for: range)
        let details = printableMonthDetails(for: months)
        guard !details.isEmpty else { return }
        PrintService.exportPaginatedPDF(
            title: monthDetailExportTitle(range: range),
            orientation: .landscape,
            pages: monthDetailPages(currency: settings.currency, details: details)
        )
    }

    private func exportMonthDetailCSV(range: MonthlyPlanExportRange) {
        guard let settings else { return }
        let months = selectedPlanMonths(for: range)
        let details = printableMonthDetails(for: months)
        guard !details.isEmpty else { return }
        let data = ExportService.monthDetailsCSVData(details: details, currency: settings.currency)
        ExportService.saveCSV(data: data, suggestedFilename: "\(monthDetailExportTitle(range: range)).csv")
    }
}
