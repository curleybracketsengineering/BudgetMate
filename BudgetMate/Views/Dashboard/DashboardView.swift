import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query private var settingsList: [AppSettings]
    @Query(sort: \BankAccount.displayOrder) private var accounts: [BankAccount]
    @Query(sort: [SortDescriptor(\BudgetMonth.year), SortDescriptor(\BudgetMonth.month)]) private var allMonths: [BudgetMonth]
    @Query private var allTiles: [BudgetTile]

    @State private var selectedAccountId: UUID?

    private var settings: AppSettings? { settingsList.first }
    private var currency: AppCurrency { settings?.currency ?? .GBP }

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

    private var forecastPoints: [AccountForecastPoint] {
        guard let settings else { return [] }
        return CashFlowService.forecastPoints(
            accounts: accounts,
            tiles: allTiles,
            settings: settings
        )
    }

    private var chartPoints: [AccountForecastPoint] {
        guard let selectedAccountId else { return forecastPoints }
        return forecastPoints.filter { $0.accountId == selectedAccountId }
    }

    private var currentMonth: BudgetMonth? {
        orderedMonths.first
    }

    var body: some View {
        Group {
            if let settings {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        accountCards(settings: settings)
                        forecastSection
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "No plan yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Complete setup to see your cash position.")
                )
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem {
                Button {
                    printDashboard()
                } label: {
                    Label("Print", systemImage: "printer")
                }
                .disabled(settings == nil || accounts.isEmpty)
                .help("Print account balances and forecast")
            }
        }
        .onAppear {
            if selectedAccountId == nil, accounts.count == 1 {
                selectedAccountId = accounts.first?.id
            }
        }
    }

    @ViewBuilder
    private func accountCards(settings: AppSettings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account balances")
                .font(.title2.weight(.semibold))

            if accounts.isEmpty {
                Text("No accounts configured.")
                    .foregroundStyle(.secondary)
            } else if let month = currentMonth {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 12) {
                    ForEach(accounts) { account in
                        let balance = accountBalance(for: account, month: month, settings: settings)
                        let level = CashFlowService.thresholdLevel(balance: balance, settings: settings)
                        AccountBalanceCard(
                            account: account,
                            balance: balance,
                            currency: currency,
                            thresholdLevel: account.isPrimary ? level : nil,
                            isSelected: selectedAccountId == account.id
                        )
                        .onTapGesture {
                            selectedAccountId = account.id
                        }
                    }
                }

                if let month = orderedMonths.last, month.id != currentMonth?.id {
                    HStack {
                        Text("End of plan (\(month.displayTitle))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(MoneyFormatter.format(
                            minorUnits: month.closingBalanceMinorUnits,
                            currency: currency
                        ))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var forecastSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Forecast")
                    .font(.title2.weight(.semibold))
                Spacer()
                if accounts.count > 1 {
                    Picker("Account", selection: $selectedAccountId) {
                        Text("All accounts").tag(Optional<UUID>.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    .frame(width: 180)
                }
            }

            if chartPoints.isEmpty {
                ContentUnavailableView(
                    "No forecast data",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Add rules and generate tiles to see your forecast.")
                )
                .frame(minHeight: 200)
            } else {
                Chart(chartPoints) { point in
                    if selectedAccountId == nil {
                        LineMark(
                            x: .value("Month", point.monthLabel),
                            y: .value("Balance", Double(point.closingBalanceMinorUnits) / Double(currency.minorUnitDivisor))
                        )
                        .foregroundStyle(by: .value("Account", point.accountName))
                        .symbol(by: .value("Account", point.accountName))
                    } else {
                        LineMark(
                            x: .value("Month", point.monthLabel),
                            y: .value("Balance", Double(point.closingBalanceMinorUnits) / Double(currency.minorUnitDivisor))
                        )
                        .foregroundStyle(Color.accentColor)
                        AreaMark(
                            x: .value("Month", point.monthLabel),
                            y: .value("Balance", Double(point.closingBalanceMinorUnits) / Double(currency.minorUnitDivisor))
                        )
                        .foregroundStyle(Color.accentColor.opacity(0.15))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(MoneyFormatter.format(
                                    minorUnits: Int((amount * Double(currency.minorUnitDivisor)).rounded()),
                                    currency: currency
                                ))
                                .font(.caption2)
                            }
                        }
                    }
                }
                .frame(minHeight: 260)
            }
        }
    }

    private func accountBalance(
        for account: BankAccount,
        month: BudgetMonth,
        settings: AppSettings
    ) -> Int {
        CashFlowService.accountBalances(
            for: month,
            accounts: accounts,
            tiles: allTiles,
            settings: settings
        )
        .first(where: { $0.accountId == account.id })?
        .closingBalanceMinorUnits ?? account.startingBalanceMinorUnits
    }

    private func printDashboard() {
        guard let settings, let currentMonth else { return }

        let printableAccounts = accounts.map { account in
            let balance = accountBalance(for: account, month: currentMonth, settings: settings)
            let level = account.isPrimary
                ? CashFlowService.thresholdLevel(balance: balance, settings: settings)
                : nil
            return PrintableAccountBalance(
                id: account.id,
                name: account.name,
                balance: balance,
                isPrimary: account.isPrimary,
                thresholdLabel: thresholdLabel(for: level)
            )
        }

        let lastMonth = orderedMonths.last
        let endLabel = lastMonth?.displayTitle
        let endBalance = lastMonth?.closingBalanceMinorUnits

        let accountNameMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        let forecastByMonth = Dictionary(grouping: forecastPoints, by: \.monthKey)
        let sortedMonthKeys = forecastByMonth.keys.sorted()
        let printableForecast = sortedMonthKeys.compactMap { key -> PrintableForecastMonth? in
            guard let points = forecastByMonth[key], let first = points.first else { return nil }
            let balances = Dictionary(uniqueKeysWithValues: points.map { ($0.accountId, $0.closingBalanceMinorUnits) })
            return PrintableForecastMonth(
                id: key,
                label: first.monthLabel,
                balancesByAccount: balances
            )
        }

        PrintService.print(title: "Dashboard") {
            DashboardPrintView(
                currency: currency,
                accounts: printableAccounts,
                endOfPlanLabel: endLabel,
                endOfPlanBalance: endBalance,
                forecastMonths: printableForecast,
                accountNames: accountNameMap
            )
        }
    }

    private func thresholdLabel(for level: BalanceThresholdLevel?) -> String? {
        guard let level else { return nil }
        switch level {
        case .safe: return "Safe"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

private struct AccountBalanceCard: View {
    let account: BankAccount
    let balance: Int
    let currency: AppCurrency
    var thresholdLevel: BalanceThresholdLevel?
    var isSelected: Bool = false

    private var accentColor: Color {
        switch thresholdLevel {
        case .none: .primary
        case .some(.safe): .green
        case .some(.warning): .orange
        case .some(.critical): .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(account.name)
                    .font(.subheadline.weight(.medium))
                if account.isPrimary {
                    Text("Primary")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }

            Text(MoneyFormatter.format(minorUnits: balance, currency: currency))
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(thresholdLevel != nil ? accentColor : .primary)

            if thresholdLevel != nil {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(height: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}
