import Foundation
import SwiftData

struct BankImportResult {
    let tilesCreated: Int
    let monthsAffected: Set<String>
    let tileIDs: [UUID]
}

enum BankImportService {
    static func importTiles(
        rows: [ImportPreviewRow],
        in context: ModelContext
    ) throws -> BankImportResult {
        let settings = try AppDataService.ensureSettings(in: context)
        _ = try BankAccountService.ensurePrimaryAccount(settings: settings, in: context)
        let accounts = try BankAccountService.fetchAll(in: context)

        var created = 0
        var monthsAffected = Set<String>()
        var tileIDs: [UUID] = []
        for row in rows {
            let tile = makeTile(from: row, accounts: accounts, in: context)
            context.insert(tile)
            created += 1
            monthsAffected.insert(tile.monthKey)
            tileIDs.append(tile.id)
        }

        try AppDataService.refreshForecast(in: context)
        return BankImportResult(tilesCreated: created, monthsAffected: monthsAffected, tileIDs: tileIDs)
    }

    static func deleteTiles(ids: [UUID], in context: ModelContext) throws {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let tiles = try context.fetch(FetchDescriptor<BudgetTile>())
        for tile in tiles where idSet.contains(tile.id) {
            context.delete(tile)
        }
        try context.save()
        try AppDataService.refreshForecast(in: context)
    }

    static func makeTile(from row: ImportPreviewRow, accounts: [BankAccount], in context: ModelContext) -> BudgetTile {
        let transaction = row.transaction
        let tile = BudgetTile(
            year: transaction.year,
            month: transaction.month,
            name: transaction.payee
        )
        tile.amountMinorUnits = transaction.amountMinorUnits
        tile.type = row.budgetType
        BudgetRuleSubCategoryService.assignSubCategory(to: tile, title: row.suggestedSubCategoryTitle, in: context)
        tile.source = .imported
        tile.status = .active
        tile.confidence = .estimated
        tile.commitment = commitment(for: row)
        tile.notes = transaction.memo
        if let matchedAccount = BankAccountService.accountForImportAlias(transaction.account, accounts: accounts),
           !matchedAccount.isPrimary {
            tile.linkedAccountId = matchedAccount.id
        }
        tile.markCreated()
        return tile
    }

    private static func commitment(for row: ImportPreviewRow) -> CommitmentType {
        switch row.budgetType {
        case .expense where row.suggestedSubCategoryTitle == "Spending":
            return .flexible
        default:
            return .known
        }
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
