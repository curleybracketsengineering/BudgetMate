import Foundation
import SwiftData

enum AppDataService {
    static func ensureSettings(in context: ModelContext) throws -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        settings.markCreated()
        context.insert(settings)
        try context.save()
        return settings
    }

    static func ensureMonths(
        settings: AppSettings,
        in context: ModelContext
    ) throws -> [BudgetMonth] {
        let existing = try context.fetch(FetchDescriptor<BudgetMonth>())
        let existingKeys = Set(existing.map(\.monthKey))
        let sequence = PlanningCalendar.monthSequence(
            startYear: settings.planningStartYear,
            startMonth: settings.planningStartMonth,
            count: settings.horizonMonths
        )

        for slot in sequence {
            let key = "\(slot.year)-\(slot.month)"
            if existingKeys.contains(key) { continue }
            let month = BudgetMonth(year: slot.year, month: slot.month)
            month.markCreated()
            context.insert(month)
        }

        try trimMonthsBeyondHorizon(settings: settings, in: context)
        try context.save()

        return try fetchMonths(settings: settings, in: context)
    }

    static func trimMonthsBeyondHorizon(settings: AppSettings, in context: ModelContext) throws {
        let sequence = PlanningCalendar.monthSequence(
            startYear: settings.planningStartYear,
            startMonth: settings.planningStartMonth,
            count: settings.horizonMonths
        )
        let validKeys = Set(sequence.map { "\($0.year)-\($0.month)" })
        let allMonths = try context.fetch(FetchDescriptor<BudgetMonth>())
        for month in allMonths where !validKeys.contains(month.monthKey) && !month.isLocked {
            context.delete(month)
        }
    }

    static func fetchMonths(settings: AppSettings, in context: ModelContext) throws -> [BudgetMonth] {
        let all = try context.fetch(FetchDescriptor<BudgetMonth>())
        let sequence = PlanningCalendar.monthSequence(
            startYear: settings.planningStartYear,
            startMonth: settings.planningStartMonth,
            count: settings.horizonMonths
        )
        let order = sequence.map { "\($0.year)-\($0.month)" }
        let byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.monthKey, $0) })
        return order.compactMap { byKey[$0] }
    }

    static func fetchAllTiles(in context: ModelContext) throws -> [BudgetTile] {
        try context.fetch(FetchDescriptor<BudgetTile>())
    }

    static func fetchAllRules(in context: ModelContext) throws -> [BudgetRule] {
        try context.fetch(FetchDescriptor<BudgetRule>())
    }

    static func fetchAllAccounts(in context: ModelContext) throws -> [BankAccount] {
        try BankAccountService.fetchAll(in: context)
    }

    static func refreshForecast(in context: ModelContext) throws {
        let settings = try ensureSettings(in: context)
        _ = try BankAccountService.ensurePrimaryAccount(settings: settings, in: context)
        let accounts = try fetchAllAccounts(in: context)
        let months = try ensureMonths(settings: settings, in: context)
        let tiles = try fetchAllTiles(in: context)
        CashFlowService.recalculate(settings: settings, accounts: accounts, months: months, tiles: tiles)
        settings.markUpdated()
        try context.save()
    }

    static func generateAndRefresh(in context: ModelContext) throws {
        let settings = try ensureSettings(in: context)
        _ = try BankAccountService.ensurePrimaryAccount(settings: settings, in: context)
        let accounts = try fetchAllAccounts(in: context)
        let months = try ensureMonths(settings: settings, in: context)
        let rules = try fetchAllRules(in: context)
        let existingTiles = try fetchAllTiles(in: context)

        let newTiles = BudgetGenerationService.generateTiles(
            rules: rules,
            settings: settings,
            months: months,
            existingTiles: existingTiles
        )
        for tile in newTiles {
            context.insert(tile)
        }

        let allTiles = existingTiles + newTiles
        CashFlowService.recalculate(settings: settings, accounts: accounts, months: months, tiles: allTiles)
        settings.markUpdated()
        try context.save()
    }
}
