import Foundation
import SwiftData

struct BankImportResult {
    let tilesCreated: Int
    let monthsAffected: Set<String>
}

enum BankImportService {
    static func importTiles(
        rows: [ImportPreviewRow],
        in context: ModelContext
    ) throws -> BankImportResult {
        var created = 0
        var monthsAffected = Set<String>()
        let settings = try AppDataService.ensureSettings(in: context)
        _ = try BankAccountService.ensurePrimaryAccount(settings: settings, in: context)
        let accounts = try BankAccountService.fetchAll(in: context)

        for row in rows {
            let transaction = row.transaction
            let tile = BudgetTile(
                year: transaction.year,
                month: transaction.month,
                name: transaction.payee
            )
            tile.amountMinorUnits = transaction.amountMinorUnits
            tile.type = row.budgetType
            tile.category = row.category
            tile.source = .imported
            tile.status = .active
            tile.confidence = .estimated
            tile.commitment = .known
            tile.notes = transaction.memo
            if let matchedAccount = BankAccountService.accountForImportAlias(transaction.account, accounts: accounts),
               !matchedAccount.isPrimary {
                tile.linkedAccountId = matchedAccount.id
            }
            tile.markCreated()
            context.insert(tile)
            created += 1
            monthsAffected.insert("\(transaction.year)-\(transaction.month)")
        }

        try AppDataService.refreshForecast(in: context)
        return BankImportResult(tilesCreated: created, monthsAffected: monthsAffected)
    }

    static func summaryTotals(for rows: [ImportPreviewRow]) -> MonthTotals {
        var totals = MonthTotals()
        for row in rows {
            let amount = row.transaction.amountMinorUnits
            switch row.budgetType {
            case .income: totals.income += amount
            case .expense: totals.expense += amount
            case .saving: totals.saving += amount
            case .transfer: totals.transfer += amount
            case .adjustment: totals.adjustment += amount
            }
        }
        return totals
    }
}
