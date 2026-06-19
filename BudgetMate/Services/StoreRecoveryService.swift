import Foundation
import SwiftData

enum StoreConfiguration: String {
    case cloud = "BudgetMateCloud"
    case local = "BudgetMateLocal"

    var alternate: StoreConfiguration {
        self == .cloud ? .local : .cloud
    }
}

struct StoreRecoveryResult {
    let source: StoreConfiguration
    let rulesAdded: Int
    let tilesAdded: Int
    let accountsAdded: Int
    let monthsAdded: Int
    let subCategoriesAdded: Int
    let payeeNotesAdded: Int

    var didRecover: Bool {
        rulesAdded + tilesAdded + accountsAdded + monthsAdded + subCategoriesAdded + payeeNotesAdded > 0
    }
}

enum StoreRecoveryService {
    @discardableResult
    static func recoverFromAlternateStoreIfNeeded(
        in context: ModelContext,
        activeConfiguration: StoreConfiguration
    ) throws -> StoreRecoveryResult? {
        let alternate = activeConfiguration.alternate
        guard let alternateContainer = ModelContainerFactory.makeContainer(configuration: alternate) else {
            return nil
        }

        let alternateContext = ModelContext(alternateContainer)
        alternateContext.autosaveEnabled = false

        let activeRuleCount = try context.fetchCount(FetchDescriptor<BudgetRule>())
        let alternateRuleCount = try alternateContext.fetchCount(FetchDescriptor<BudgetRule>())

        guard alternateRuleCount > activeRuleCount else { return nil }

        let result = try mergeEntities(from: alternateContext, into: context)
        try AppDataService.refreshForecast(in: context)
        return StoreRecoveryResult(
            source: alternate,
            rulesAdded: result.rulesAdded,
            tilesAdded: result.tilesAdded,
            accountsAdded: result.accountsAdded,
            monthsAdded: result.monthsAdded,
            subCategoriesAdded: result.subCategoriesAdded,
            payeeNotesAdded: result.payeeNotesAdded
        )
    }

    static func ruleCount(in configuration: StoreConfiguration) -> Int? {
        guard let container = ModelContainerFactory.makeContainer(configuration: configuration) else {
            return nil
        }
        let context = ModelContext(container)
        return try? context.fetchCount(FetchDescriptor<BudgetRule>())
    }

    // MARK: - Private

    private struct MergeCounts {
        var rulesAdded = 0
        var tilesAdded = 0
        var accountsAdded = 0
        var monthsAdded = 0
        var subCategoriesAdded = 0
        var payeeNotesAdded = 0
    }

    private static func mergeEntities(
        from source: ModelContext,
        into destination: ModelContext
    ) throws -> MergeCounts {
        var counts = MergeCounts()

        let existingAccountIDs = Set(try destination.fetch(FetchDescriptor<BankAccount>()).map(\.id))
        for account in try source.fetch(FetchDescriptor<BankAccount>()) where !existingAccountIDs.contains(account.id) {
            let copy = BankAccount(name: account.name, isPrimary: account.isPrimary)
            copy.id = account.id
            copy.startingBalanceMinorUnits = account.startingBalanceMinorUnits
            copy.displayOrder = account.displayOrder
            copy.importAlias = account.importAlias
            copy.createdAt = account.createdAt
            copy.updatedAt = account.updatedAt
            copy.deviceId = account.deviceId
            destination.insert(copy)
            counts.accountsAdded += 1
        }

        var subCategoryByID: [UUID: BudgetRuleSubCategory] = [:]
        for subCategory in try destination.fetch(FetchDescriptor<BudgetRuleSubCategory>()) {
            subCategoryByID[subCategory.id] = subCategory
        }
        for subCategory in try source.fetch(FetchDescriptor<BudgetRuleSubCategory>()) where subCategoryByID[subCategory.id] == nil {
            let copy = BudgetRuleSubCategory(
                title: subCategory.title,
                orderGroup: subCategory.orderGroup,
                sortOrder: subCategory.sortOrder
            )
            copy.id = subCategory.id
            destination.insert(copy)
            subCategoryByID[copy.id] = copy
            counts.subCategoriesAdded += 1
        }

        let existingRuleIDs = Set(try destination.fetch(FetchDescriptor<BudgetRule>()).map(\.id))
        for rule in try source.fetch(FetchDescriptor<BudgetRule>()) where !existingRuleIDs.contains(rule.id) {
            let copy = BudgetRule()
            copy.id = rule.id
            copy.name = rule.name
            copy.type = rule.type
            copy.category = rule.category
            copy.amountMinorUnits = rule.amountMinorUnits
            copy.monthlyEquivalentMinorUnits = rule.monthlyEquivalentMinorUnits
            copy.cycle = rule.cycle
            copy.startDate = rule.startDate
            copy.endDate = rule.endDate
            copy.isActive = rule.isActive
            copy.isArchived = rule.isArchived
            copy.confidence = rule.confidence
            copy.commitment = rule.commitment
            copy.assumptionsNotes = rule.assumptionsNotes
            copy.monthPatternRaw = rule.monthPatternRaw
            copy.linkedAccountId = rule.linkedAccountId
            copy.transferToAccountId = rule.transferToAccountId
            copy.showIndividuallyInPlan = rule.showIndividuallyInPlan
            copy.displayOrder = rule.displayOrder
            copy.createdAt = rule.createdAt
            copy.updatedAt = rule.updatedAt
            copy.deviceId = rule.deviceId
            if let sourceSubCategory = rule.subCategory {
                copy.subCategory = subCategoryByID[sourceSubCategory.id]
            }
            destination.insert(copy)
            counts.rulesAdded += 1
        }

        let existingMonthKeys = Set(try destination.fetch(FetchDescriptor<BudgetMonth>()).map(\.monthKey))
        for month in try source.fetch(FetchDescriptor<BudgetMonth>()) where !existingMonthKeys.contains(month.monthKey) {
            let copy = BudgetMonth(year: month.year, month: month.month)
            copy.id = month.id
            copy.openingBalanceMinorUnits = month.openingBalanceMinorUnits
            copy.closingBalanceMinorUnits = month.closingBalanceMinorUnits
            copy.isLocked = month.isLocked
            copy.notes = month.notes
            copy.createdAt = month.createdAt
            copy.updatedAt = month.updatedAt
            copy.deviceId = month.deviceId
            destination.insert(copy)
            counts.monthsAdded += 1
        }

        let existingTileIDs = Set(try destination.fetch(FetchDescriptor<BudgetTile>()).map(\.id))
        for tile in try source.fetch(FetchDescriptor<BudgetTile>()) where !existingTileIDs.contains(tile.id) {
            let copy = BudgetTile(year: tile.year, month: tile.month, name: tile.name)
            copy.id = tile.id
            copy.amountMinorUnits = tile.amountMinorUnits
            copy.type = tile.type
            copy.category = tile.category
            copy.source = tile.source
            copy.status = tile.status
            copy.confidence = tile.confidence
            copy.commitment = tile.commitment
            copy.linkedRuleId = tile.linkedRuleId
            copy.recurringOccurrenceIndex = tile.recurringOccurrenceIndex
            copy.linkedHolidayActivityId = tile.linkedHolidayActivityId
            copy.linkedAccountId = tile.linkedAccountId
            copy.transferToAccountId = tile.transferToAccountId
            copy.notes = tile.notes
            copy.createdAt = tile.createdAt
            copy.updatedAt = tile.updatedAt
            copy.deviceId = tile.deviceId
            if let sourceSubCategory = tile.subCategory {
                copy.subCategory = subCategoryByID[sourceSubCategory.id]
            }
            destination.insert(copy)
            counts.tilesAdded += 1
        }

        let existingPayeeKeys = Set(try destination.fetch(FetchDescriptor<PayeeNote>()).map(\.matchKey))
        for note in try source.fetch(FetchDescriptor<PayeeNote>()) where !existingPayeeKeys.contains(note.matchKey) {
            let copy = PayeeNote()
            copy.id = note.id
            copy.matchKey = note.matchKey
            copy.displayName = note.displayName
            copy.notes = note.notes
            copy.samplePayee = note.samplePayee
            copy.createdAt = note.createdAt
            copy.updatedAt = note.updatedAt
            copy.deviceId = note.deviceId
            destination.insert(copy)
            counts.payeeNotesAdded += 1
        }

        try destination.save()
        return counts
    }
}
