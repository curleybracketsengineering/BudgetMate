import Foundation
import SwiftData

struct MonthTotals {
    var income: Int = 0
    var expense: Int = 0
    var saving: Int = 0
    var transfer: Int = 0
    var adjustment: Int = 0

    func closingBalance(opening: Int) -> Int {
        opening + income - expense - saving + adjustment
    }
}

struct AccountMonthBalance {
    let accountId: UUID
    let openingBalanceMinorUnits: Int
    let closingBalanceMinorUnits: Int
}

struct AccountForecastPoint: Identifiable {
    let id: String
    let accountId: UUID
    let accountName: String
    let monthKey: String
    let monthLabel: String
    let closingBalanceMinorUnits: Int
}

enum CashFlowService {
    static func totals(for tiles: [BudgetTile]) -> MonthTotals {
        var result = MonthTotals()
        for tile in tiles where tile.isActive {
            switch tile.type {
            case .income: result.income += tile.amountMinorUnits
            case .expense: result.expense += tile.amountMinorUnits
            case .saving: result.saving += tile.amountMinorUnits
            case .transfer: result.transfer += tile.amountMinorUnits
            case .adjustment: result.adjustment += tile.amountMinorUnits
            }
        }
        return result
    }

    static func thresholdLevel(
        balance: Int,
        settings: AppSettings
    ) -> BalanceThresholdLevel {
        if balance < settings.criticalThresholdMinorUnits { return .critical }
        if balance < settings.warningThresholdMinorUnits { return .warning }
        if balance < settings.safeThresholdMinorUnits { return .warning }
        return .safe
    }

    static func recalculate(
        settings: AppSettings,
        accounts: [BankAccount],
        months: [BudgetMonth],
        tiles: [BudgetTile]
    ) {
        let sequence = PlanningCalendar.monthSequence(
            startYear: settings.planningStartYear,
            startMonth: settings.planningStartMonth,
            count: settings.horizonMonths
        )

        let monthsByKey = months.keyedByMonthKey()
        let activeTiles = tiles.filter(\.isActive)
        let tilesByKey = Dictionary(grouping: activeTiles) { $0.monthKey }

        var previousClosingsByAccount = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0.startingBalanceMinorUnits) }
        )

        for (index, slot) in sequence.enumerated() {
            let key = "\(slot.year)-\(slot.month)"
            guard let month = monthsByKey[key] else { continue }

            if month.isLocked {
                previousClosingsByAccount = lockedMonthClosings(
                    accounts: accounts,
                    monthTiles: tilesByKey[key] ?? [],
                    openingByAccount: previousClosingsByAccount,
                    accountsList: accounts
                )
                continue
            }

            let monthTiles = tilesByKey[key] ?? []
            var aggregateOpening = 0
            var aggregateClosing = 0

            for account in accounts {
                let opening = index == 0
                    ? account.startingBalanceMinorUnits
                    : (previousClosingsByAccount[account.id] ?? account.startingBalanceMinorUnits)
                let closing = closingBalance(
                    for: account.id,
                    opening: opening,
                    monthTiles: monthTiles,
                    accounts: accounts
                )

                previousClosingsByAccount[account.id] = closing
                aggregateOpening += opening
                aggregateClosing += closing
            }

            month.openingBalanceMinorUnits = aggregateOpening
            month.closingBalanceMinorUnits = aggregateClosing
            month.markUpdated()
        }

        syncPrimaryStartingBalance(settings: settings, accounts: accounts)
    }

    static func accountBalances(
        for month: BudgetMonth,
        accounts: [BankAccount],
        tiles: [BudgetTile],
        settings: AppSettings
    ) -> [AccountMonthBalance] {
        let sequence = PlanningCalendar.monthSequence(
            startYear: settings.planningStartYear,
            startMonth: settings.planningStartMonth,
            count: settings.horizonMonths
        )

        var closingsByAccount = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0.startingBalanceMinorUnits) }
        )

        for slot in sequence {
            let key = "\(slot.year)-\(slot.month)"
            let monthTiles = tiles.filter { $0.monthKey == key && $0.isActive }
            var openingsByAccount: [UUID: Int] = [:]

            for account in accounts {
                let opening = closingsByAccount[account.id] ?? account.startingBalanceMinorUnits
                openingsByAccount[account.id] = opening
                closingsByAccount[account.id] = closingBalance(
                    for: account.id,
                    opening: opening,
                    monthTiles: monthTiles,
                    accounts: accounts
                )
            }

            if key == month.monthKey {
                return accounts.map { account in
                    AccountMonthBalance(
                        accountId: account.id,
                        openingBalanceMinorUnits: openingsByAccount[account.id] ?? account.startingBalanceMinorUnits,
                        closingBalanceMinorUnits: closingsByAccount[account.id] ?? account.startingBalanceMinorUnits
                    )
                }
            }
        }

        return []
    }

    static func forecastPoints(
        accounts: [BankAccount],
        tiles: [BudgetTile],
        settings: AppSettings
    ) -> [AccountForecastPoint] {
        let sequence = PlanningCalendar.monthSequence(
            startYear: settings.planningStartYear,
            startMonth: settings.planningStartMonth,
            count: settings.horizonMonths
        )

        let activeTiles = tiles.filter(\.isActive)
        let tilesByKey = Dictionary(grouping: activeTiles) { $0.monthKey }
        var closingsByAccount = Dictionary(
            uniqueKeysWithValues: accounts.map { ($0.id, $0.startingBalanceMinorUnits) }
        )

        var points: [AccountForecastPoint] = []

        for slot in sequence {
            let key = "\(slot.year)-\(slot.month)"
            let monthTiles = tilesByKey[key] ?? []

            for account in accounts {
                let opening = closingsByAccount[account.id] ?? account.startingBalanceMinorUnits
                let closing = closingBalance(
                    for: account.id,
                    opening: opening,
                    monthTiles: monthTiles,
                    accounts: accounts
                )
                closingsByAccount[account.id] = closing

                points.append(AccountForecastPoint(
                    id: "\(account.id)-\(key)",
                    accountId: account.id,
                    accountName: account.name,
                    monthKey: key,
                    monthLabel: monthLabel(year: slot.year, month: slot.month),
                    closingBalanceMinorUnits: closing
                ))
            }
        }

        return points
    }

    static func tilesForMonth(
        year: Int,
        month: Int,
        from tiles: [BudgetTile]
    ) -> [BudgetTile] {
        tiles.filter { $0.year == year && $0.month == month && $0.isActive }
    }

    static func closingBalance(
        for accountId: UUID,
        opening: Int,
        monthTiles: [BudgetTile],
        accounts: [BankAccount]
    ) -> Int {
        var balance = opening
        for tile in monthTiles where tile.isActive {
            let sourceId = BankAccountService.resolvedAccountId(
                linkedAccountId: tile.linkedAccountId,
                accounts: accounts
            )

            switch tile.type {
            case .income:
                if sourceId == accountId { balance += tile.amountMinorUnits }
            case .expense, .saving:
                if sourceId == accountId { balance -= tile.amountMinorUnits }
            case .transfer:
                if sourceId == accountId { balance -= tile.amountMinorUnits }
                if tile.transferToAccountId == accountId { balance += tile.amountMinorUnits }
            case .adjustment:
                if sourceId == accountId { balance += tile.amountMinorUnits }
            }
        }
        return balance
    }

    private static func syncPrimaryStartingBalance(settings: AppSettings, accounts: [BankAccount]) {
        guard let primary = BankAccountService.primaryAccount(from: accounts) else { return }
        settings.startingBalanceMinorUnits = primary.startingBalanceMinorUnits
    }

    private static func lockedMonthClosings(
        accounts: [BankAccount],
        monthTiles: [BudgetTile],
        openingByAccount: [UUID: Int],
        accountsList: [BankAccount]
    ) -> [UUID: Int] {
        var result = openingByAccount
        for account in accounts {
            let opening = openingByAccount[account.id] ?? account.startingBalanceMinorUnits
            result[account.id] = closingBalance(
                for: account.id,
                opening: opening,
                monthTiles: monthTiles,
                accounts: accountsList
            )
        }
        return result
    }

    private static func monthLabel(year: Int, month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else {
            return "\(month)/\(year)"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yy"
        return formatter.string(from: date)
    }
}
