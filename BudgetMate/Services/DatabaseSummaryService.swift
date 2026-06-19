import Foundation
import SwiftData

struct DatabaseSummary {
    struct RuleTypeCount: Identifiable {
        let type: BudgetType
        let count: Int
        var id: String { type.rawValue }
    }

    struct TileSourceCount: Identifiable {
        let source: BudgetTileSource
        let count: Int
        var id: String { source.rawValue }
    }

    let planningPeriodLabel: String?
    let accountCount: Int
    let monthCount: Int
    let totalRules: Int
    let activeRules: Int
    let archivedRules: Int
    let incomingRules: Int
    let outgoingRules: Int
    let otherRules: Int
    let totalTiles: Int
    let activeTiles: Int
    let payeeNoteCount: Int
    let holidayCount: Int
    let subCategoryCount: Int
    let rulesByType: [RuleTypeCount]
    let tilesBySource: [TileSourceCount]
    let sampleActiveRuleNames: [String]
    let sampleArchivedRuleNames: [String]
    let tilesInHorizon: Int
    let tilesOutsideHorizon: Int
    let activeStoreName: String
    let alternateStoreName: String
    let alternateStoreRuleCount: Int?
    let canRecoverFromAlternateStore: Bool
}

enum DatabaseSummaryService {
    static func fetch(in context: ModelContext) throws -> DatabaseSummary {
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first
        let accounts = try BankAccountService.fetchAll(in: context)
        let rules = try context.fetch(FetchDescriptor<BudgetRule>())
        let tiles = try context.fetch(FetchDescriptor<BudgetTile>())
        let months = try context.fetch(FetchDescriptor<BudgetMonth>())
        let payeeNotes = try context.fetch(FetchDescriptor<PayeeNote>())
        let holidays = try context.fetch(FetchDescriptor<Holiday>())
        let subCategories = try context.fetch(FetchDescriptor<BudgetRuleSubCategory>())

        let activeRules = rules.filter { $0.isActive && !$0.isArchived }
        let archivedRules = rules.filter(\.isArchived)
        let horizonKeys: Set<String>
        if let settings {
            horizonKeys = AppDataService.planningHorizonKeys(for: settings)
        } else {
            horizonKeys = []
        }

        let rulesByType = Dictionary(grouping: activeRules, by: \.type)
            .map { DatabaseSummary.RuleTypeCount(type: $0.key, count: $0.value.count) }
            .sorted { $0.type.displayName < $1.type.displayName }

        let activeTiles = tiles.filter(\.isActive)
        let tilesBySource = Dictionary(grouping: activeTiles, by: \.source)
            .map { DatabaseSummary.TileSourceCount(source: $0.key, count: $0.value.count) }
            .sorted { $0.source.displayName < $1.source.displayName }

        let tilesInHorizon = activeTiles.filter { horizonKeys.contains($0.monthKey) }.count
        let tilesOutsideHorizon = activeTiles.count - tilesInHorizon

        let activeStore = ModelContainerFactory.activeConfiguration
        let alternateStore = activeStore.alternate
        let alternateRuleCount = StoreRecoveryService.ruleCount(in: alternateStore)

        return DatabaseSummary(
            planningPeriodLabel: settings.flatMap { BudgetRuleService.PlanningPeriod.from(settings: $0)?.label },
            accountCount: accounts.count,
            monthCount: months.count,
            totalRules: rules.count,
            activeRules: activeRules.count,
            archivedRules: archivedRules.count,
            incomingRules: BudgetRuleService.rules(in: .incoming, from: activeRules).count,
            outgoingRules: BudgetRuleService.rules(in: .outgoing, from: activeRules).count,
            otherRules: BudgetRuleService.rules(in: .other, from: activeRules).count,
            totalTiles: tiles.count,
            activeTiles: activeTiles.count,
            payeeNoteCount: payeeNotes.count,
            holidayCount: holidays.count,
            subCategoryCount: subCategories.count,
            rulesByType: rulesByType,
            tilesBySource: tilesBySource,
            sampleActiveRuleNames: activeRules.map(\.name).sorted().prefix(15).map { $0 },
            sampleArchivedRuleNames: archivedRules.map(\.name).sorted(),
            tilesInHorizon: tilesInHorizon,
            tilesOutsideHorizon: tilesOutsideHorizon,
            activeStoreName: activeStore == .cloud ? "iCloud (BudgetMateCloud)" : "Local only (BudgetMateLocal)",
            alternateStoreName: alternateStore == .cloud ? "iCloud (BudgetMateCloud)" : "Local only (BudgetMateLocal)",
            alternateStoreRuleCount: alternateRuleCount,
            canRecoverFromAlternateStore: (alternateRuleCount ?? 0) > rules.count
        )
    }
}
