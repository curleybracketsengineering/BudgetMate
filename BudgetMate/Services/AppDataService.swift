import Foundation
import SwiftData

enum AppDataService {
    /// Wipes all budget data from the active store, the alternate on-disk store, and local iCloud cache files.
    static func wipeAllPersistedData(in context: ModelContext) throws {
        try clearAllEntities(in: context)

        let active = ModelContainerFactory.activeConfiguration
        let alternate = active.alternate
        if let alternateContainer = ModelContainerFactory.makeContainer(configuration: alternate) {
            let alternateContext = ModelContext(alternateContainer)
            alternateContext.autosaveEnabled = false
            try clearAllEntities(in: alternateContext)
            try alternateContext.save()
        }

        try context.save()
        PersistedStoreService.purgeInactiveStoreFiles(keeping: active)
        PersistedStoreService.scheduleFullStorePurgeOnNextLaunch()
        PersistedStoreService.resetAuxiliaryPreferences()
    }

    static func clearAllData(in context: ModelContext) throws {
        try clearAllEntities(in: context)
        try context.save()
    }

    private static func clearAllEntities(in context: ModelContext) throws {
        for tile in try context.fetch(FetchDescriptor<BudgetTile>()) {
            context.delete(tile)
        }
        for rule in try context.fetch(FetchDescriptor<BudgetRule>()) {
            context.delete(rule)
        }
        for subCategory in try context.fetch(FetchDescriptor<BudgetRuleSubCategory>()) {
            context.delete(subCategory)
        }
        for month in try context.fetch(FetchDescriptor<BudgetMonth>()) {
            context.delete(month)
        }
        for account in try context.fetch(FetchDescriptor<BankAccount>()) {
            context.delete(account)
        }
        for note in try context.fetch(FetchDescriptor<PayeeNote>()) {
            context.delete(note)
        }
        for activity in try context.fetch(FetchDescriptor<HolidayActivity>()) {
            context.delete(activity)
        }
        for holiday in try context.fetch(FetchDescriptor<Holiday>()) {
            context.delete(holiday)
        }
        for settings in try context.fetch(FetchDescriptor<AppSettings>()) {
            context.delete(settings)
        }
    }

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
        try deduplicateMonths(in: context)

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

        try pruneStalePlanData(settings: settings, in: context)
        try context.save()

        return try fetchMonths(settings: settings, in: context)
    }

    static func planningHorizonKeys(for settings: AppSettings) -> Set<String> {
        let sequence = PlanningCalendar.monthSequence(
            startYear: settings.planningStartYear,
            startMonth: settings.planningStartMonth,
            count: settings.horizonMonths
        )
        return Set(sequence.map { "\($0.year)-\($0.month)" })
    }

    /// Removes months and tiles that fall outside the current planning horizon.
    /// Out-of-horizon data is stale after the planning start or length changes.
    static func pruneStalePlanData(settings: AppSettings, in context: ModelContext) throws {
        let validKeys = planningHorizonKeys(for: settings)

        let allMonths = try context.fetch(FetchDescriptor<BudgetMonth>())
        for month in allMonths where !validKeys.contains(month.monthKey) {
            context.delete(month)
        }

        let allTiles = try context.fetch(FetchDescriptor<BudgetTile>())
        for tile in allTiles where !validKeys.contains(tile.monthKey) {
            context.delete(tile)
        }
    }

    /// Rebuilds the plan from the current anchor month: prunes stale data, resyncs recurring tiles, and recalculates balances.
    static func reanchorPlan(settings: AppSettings, in context: ModelContext) throws {
        try pruneStalePlanData(settings: settings, in: context)
        _ = try ensureMonths(settings: settings, in: context)
        _ = try generateAndRefresh(in: context)
    }

    static func fetchMonths(settings: AppSettings, in context: ModelContext) throws -> [BudgetMonth] {
        let all = try context.fetch(FetchDescriptor<BudgetMonth>())
        let sequence = PlanningCalendar.monthSequence(
            startYear: settings.planningStartYear,
            startMonth: settings.planningStartMonth,
            count: settings.horizonMonths
        )
        let order = sequence.map { "\($0.year)-\($0.month)" }
        let byKey = all.keyedByMonthKey()
        return order.compactMap { byKey[$0] }
    }

    private static func deduplicateMonths(in context: ModelContext) throws {
        let allMonths = try context.fetch(FetchDescriptor<BudgetMonth>())
        let grouped = Dictionary(grouping: allMonths, by: \.monthKey)
        for duplicates in grouped.values where duplicates.count > 1 {
            let keeper = duplicates.dropFirst().reduce(duplicates[0], BudgetMonth.preferDuplicate)
            for month in duplicates where month.id != keeper.id {
                context.delete(month)
            }
        }
    }

    static func fetchAllTiles(in context: ModelContext) throws -> [BudgetTile] {
        try context.fetch(FetchDescriptor<BudgetTile>())
    }

    static func fetchAllRules(in context: ModelContext) throws -> [BudgetRule] {
        try deduplicateRules(in: context)
        return try context.fetch(FetchDescriptor<BudgetRule>())
    }

    private static func deduplicateRules(in context: ModelContext) throws {
        let allRules = try context.fetch(FetchDescriptor<BudgetRule>())
        let grouped = Dictionary(grouping: allRules, by: \.id)
        for duplicates in grouped.values where duplicates.count > 1 {
            let keeper = duplicates.dropFirst().reduce(duplicates[0], BudgetRule.preferDuplicate)
            for rule in duplicates where rule !== keeper {
                context.delete(rule)
            }
        }
    }

    static func fetchAllAccounts(in context: ModelContext) throws -> [BankAccount] {
        try BankAccountService.fetchAll(in: context)
    }

    static func extendHorizon(
        byYears years: Int,
        settings: AppSettings,
        maxMonths: Int,
        in context: ModelContext
    ) throws {
        guard years > 0 else { return }
        let additional = PlanningHorizon.months(forYears: years)
        settings.horizonMonths = min(settings.horizonMonths + additional, maxMonths)
        settings.markUpdated()
        _ = try ensureMonths(settings: settings, in: context)
        _ = try generateAndRefresh(in: context)
    }

    static func setHorizonMonths(
        _ months: Int,
        settings: AppSettings,
        maxMonths: Int,
        in context: ModelContext
    ) throws {
        settings.horizonMonths = min(max(months, PlanningHorizon.baseMonths), maxMonths)
        settings.markUpdated()
        _ = try ensureMonths(settings: settings, in: context)
        try refreshForecast(in: context)
    }

    static func refreshForecast(in context: ModelContext) throws {
        try deduplicateRules(in: context)
        let settings = try ensureSettings(in: context)
        _ = try BankAccountService.ensurePrimaryAccount(settings: settings, in: context)
        try pruneStalePlanData(settings: settings, in: context)
        let accounts = try fetchAllAccounts(in: context)
        let months = try ensureMonths(settings: settings, in: context)
        let tiles = try fetchAllTiles(in: context)
        CashFlowService.recalculate(settings: settings, accounts: accounts, months: months, tiles: tiles)
        settings.markUpdated()
        try context.save()
    }

    static func syncRuleTilesAndRefresh(rule: BudgetRule, in context: ModelContext) throws {
        let settings = try ensureSettings(in: context)
        _ = try BankAccountService.ensurePrimaryAccount(settings: settings, in: context)
        let accounts = try fetchAllAccounts(in: context)
        let months = try ensureMonths(settings: settings, in: context)
        let tiles = try fetchAllTiles(in: context)
        _ = BudgetGenerationService.syncTiles(
            for: rule,
            settings: settings,
            months: months,
            allTiles: tiles,
            in: context
        )
        let allTiles = try fetchAllTiles(in: context)
        CashFlowService.recalculate(settings: settings, accounts: accounts, months: months, tiles: allTiles)
        settings.markUpdated()
        try context.save()
    }

    @discardableResult
    static func generateAndRefresh(in context: ModelContext) throws -> Int {
        let settings = try ensureSettings(in: context)
        _ = try BankAccountService.ensurePrimaryAccount(settings: settings, in: context)
        let accounts = try fetchAllAccounts(in: context)
        let months = try ensureMonths(settings: settings, in: context)
        let rules = try fetchAllRules(in: context)

        var totalAdded = 0
        for rule in rules {
            let tiles = try fetchAllTiles(in: context)
            let result = BudgetGenerationService.syncTiles(
                for: rule,
                settings: settings,
                months: months,
                allTiles: tiles,
                in: context
            )
            totalAdded += result.added
        }

        let allTiles = try fetchAllTiles(in: context)
        CashFlowService.recalculate(settings: settings, accounts: accounts, months: months, tiles: allTiles)
        settings.markUpdated()
        try context.save()
        return totalAdded
    }
}
