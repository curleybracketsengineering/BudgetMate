import SwiftUI
import SwiftData

struct MonthDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query private var allTiles: [BudgetTile]
    @Query private var rules: [BudgetRule]
    @Query(sort: \BankAccount.displayOrder) private var accounts: [BankAccount]

    let month: BudgetMonth

    @State private var showingAddTile = false
    @State private var editingTile: BudgetTile?

    private var settings: AppSettings? { settingsList.first }
    private var currency: AppCurrency { settings?.currency ?? .GBP }

    private var monthTiles: [BudgetTile] {
        CashFlowService.tilesForMonth(year: month.year, month: month.month, from: allTiles)
    }

    private var totals: MonthTotals {
        CashFlowService.totals(for: monthTiles)
    }

    private var hasMultipleAccounts: Bool {
        accounts.count > 1
    }

    private var accountBalances: [AccountMonthBalance] {
        guard let settings else { return [] }
        return CashFlowService.accountBalances(
            for: month,
            accounts: accounts,
            tiles: allTiles,
            settings: settings
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                summaryCards
                if hasMultipleAccounts {
                    accountBreakdown
                }
                tilesSection
            }
            .padding()
        }
        .navigationTitle(month.displayTitle)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingAddTile) {
            BudgetTileFormView(currency: currency, defaultYear: month.year, defaultMonth: month.month)
        }
        .sheet(item: $editingTile) { tile in
            BudgetTileFormView(currency: currency, existingTile: tile, defaultYear: month.year, defaultMonth: month.month)
        }
    }

    private var header: some View {
        HStack {
            if month.isLocked {
                Label("Locked", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let level = settings.map { CashFlowService.thresholdLevel(balance: month.closingBalanceMinorUnits, settings: $0) }
            if let level {
                Text(level == .safe ? "Safe" : level == .warning ? "Warning" : "Critical")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(level == .safe ? Color.green.opacity(0.2) : level == .warning ? Color.orange.opacity(0.2) : Color.red.opacity(0.2), in: Capsule())
            }
        }
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
            SummaryCard(title: "Opening", amount: MoneyFormatter.format(minorUnits: month.openingBalanceMinorUnits, currency: currency))
            SummaryCard(title: "Income", amount: MoneyFormatter.format(minorUnits: totals.income, currency: currency), tint: .green)
            SummaryCard(title: "Expenses", amount: MoneyFormatter.format(minorUnits: totals.expense, currency: currency), tint: .red)
            SummaryCard(title: "Savings", amount: MoneyFormatter.format(minorUnits: totals.saving, currency: currency))
            SummaryCard(title: "Closing", amount: MoneyFormatter.format(minorUnits: month.closingBalanceMinorUnits, currency: currency), tint: .primary)
        }
    }

    private var accountBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By account")
                .font(.title3.weight(.semibold))

            ForEach(accounts) { account in
                if let balance = accountBalances.first(where: { $0.accountId == account.id }) {
                    HStack {
                        Text(account.name)
                            .font(.subheadline)
                        Spacer()
                        Text(MoneyFormatter.format(minorUnits: balance.closingBalanceMinorUnits, currency: currency))
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
    }

    private var displaySections: [PlanTileDisplaySection] {
        PlanTileGroupingService.displaySections(tiles: monthTiles, rules: rules)
    }

    private var tilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budget tiles")
                .font(.title3.weight(.semibold))

            if monthTiles.isEmpty {
                ContentUnavailableView("No tiles", systemImage: "tray", description: Text("Add a manual tile or generate from budget rules."))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ForEach(displaySections) { section in
                    if section.isGrouped {
                        GroupedTileRowView(
                            title: section.title,
                            itemCount: section.tiles.count,
                            totalMinorUnits: section.totalMinorUnits,
                            currency: currency,
                            tiles: section.tiles,
                            hasMultipleAccounts: hasMultipleAccounts,
                            accounts: accounts,
                            onEditTile: { editingTile = $0 }
                        )
                    } else {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(section.tiles, id: \.id) { tile in
                            TileRowView(
                                tile: tile,
                                currency: currency,
                                accountName: hasMultipleAccounts && tile.type != .transfer
                                    ? BankAccountService.accountName(for: tile.linkedAccountId, accounts: accounts)
                                    : nil,
                                transferDescription: tile.type == .transfer
                                    ? BankAccountService.transferDescription(
                                        from: tile.linkedAccountId,
                                        to: tile.transferToAccountId,
                                        accounts: accounts
                                    )
                                    : nil
                            ) {
                                editingTile = tile
                            }
                        }
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showingAddTile = true
            } label: {
                Label("Add Tile", systemImage: "plus")
            }

            Button {
                toggleLock()
            } label: {
                Label(month.isLocked ? "Unlock" : "Lock", systemImage: month.isLocked ? "lock.open" : "lock")
            }

            Button {
                recalculate()
            } label: {
                Label("Recalculate", systemImage: "arrow.clockwise")
            }
        }
    }

    private func toggleLock() {
        month.isLocked.toggle()
        month.markUpdated()
        try? modelContext.save()
    }

    private func recalculate() {
        do {
            try AppDataService.refreshForecast(in: modelContext)
        } catch {
            print("Recalculate failed: \(error)")
        }
    }
}
