import Foundation
import SwiftData

enum BudgetRuleSubCategoryService {
    private static let legacyMigrationKey = PersistedStoreService.legacySubCategoryMigrationKey

    // MARK: - Migration

    static func migrateLegacyCategoriesIfNeeded(in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: legacyMigrationKey) else { return }

        let rules = (try? context.fetch(FetchDescriptor<BudgetRule>())) ?? []
        let tiles = (try? context.fetch(FetchDescriptor<BudgetTile>())) ?? []
        var subCategories = (try? context.fetch(FetchDescriptor<BudgetRuleSubCategory>())) ?? []

        for rule in rules {
            guard rule.subCategory == nil else { continue }
            let group = BudgetRuleService.OrderGroup.forType(rule.type)
            guard group == .incoming || group == .outgoing else { continue }

            let title = rule.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            guard let subCategory = findOrCreate(
                orderGroup: group,
                title: title,
                existing: subCategories,
                in: context
            ) else { continue }
            if !subCategories.contains(where: { $0.id == subCategory.id }) {
                subCategories.append(subCategory)
            }
            rule.subCategory = subCategory
            rule.category = ""
        }

        let rulesById = rules.keyedById()
        for tile in tiles {
            guard tile.subCategory == nil else { continue }
            let group = BudgetRuleService.OrderGroup.forType(tile.type)
            guard group == .incoming || group == .outgoing else { continue }

            if let ruleId = tile.linkedRuleId, let rule = rulesById[ruleId], let subCategory = rule.subCategory {
                tile.subCategory = subCategory
                tile.category = ""
                continue
            }

            let title = tile.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            guard let subCategory = findOrCreate(
                orderGroup: group,
                title: title,
                existing: subCategories,
                in: context
            ) else { continue }
            if !subCategories.contains(where: { $0.id == subCategory.id }) {
                subCategories.append(subCategory)
            }
            tile.subCategory = subCategory
            tile.category = ""
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: legacyMigrationKey)
    }

    // MARK: - CRUD

    static func subCategories(
        for orderGroup: BudgetRuleService.OrderGroup,
        from all: [BudgetRuleSubCategory]
    ) -> [BudgetRuleSubCategory] {
        all
            .filter { $0.orderGroup == orderGroup }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    @discardableResult
    static func addSubCategory(
        orderGroup: BudgetRuleService.OrderGroup,
        title: String,
        existing: [BudgetRuleSubCategory],
        in context: ModelContext
    ) -> BudgetRuleSubCategory? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let inGroup = subCategories(for: orderGroup, from: existing)
        let next = (inGroup.map(\.sortOrder).max() ?? -1) + 1
        let subCategory = BudgetRuleSubCategory(title: trimmed, orderGroup: orderGroup, sortOrder: next)
        context.insert(subCategory)
        try? context.save()
        return subCategory
    }

    static func renameSubCategory(_ subCategory: BudgetRuleSubCategory, to title: String, in context: ModelContext) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subCategory.title = trimmed
        try? context.save()
    }

    static func deleteSubCategory(_ subCategory: BudgetRuleSubCategory, in context: ModelContext) {
        for rule in subCategory.rules {
            rule.subCategory = nil
        }
        let tiles = (try? context.fetch(FetchDescriptor<BudgetTile>())) ?? []
        for tile in tiles where tile.subCategory?.id == subCategory.id {
            tile.subCategory = nil
        }
        context.delete(subCategory)
        try? context.save()
    }

    static func persistSortOrder(_ ordered: [BudgetRuleSubCategory], in context: ModelContext) {
        for (index, subCategory) in ordered.enumerated() {
            subCategory.sortOrder = index
        }
        try? context.save()
    }

    @discardableResult
    static func findOrCreate(
        orderGroup: BudgetRuleService.OrderGroup,
        title: String,
        in context: ModelContext
    ) -> BudgetRuleSubCategory? {
        let all = (try? context.fetch(FetchDescriptor<BudgetRuleSubCategory>())) ?? []
        return findOrCreate(orderGroup: orderGroup, title: title, existing: all, in: context)
    }

    @discardableResult
    static func findOrCreate(
        orderGroup: BudgetRuleService.OrderGroup,
        title: String,
        existing: [BudgetRuleSubCategory],
        in context: ModelContext
    ) -> BudgetRuleSubCategory? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let match = existing.first(where: {
            $0.orderGroup == orderGroup && $0.title.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return match
        }

        return addSubCategory(orderGroup: orderGroup, title: trimmed, existing: existing, in: context)
    }

    static func assignSubCategory(
        to rule: BudgetRule,
        title: String,
        in context: ModelContext
    ) {
        guard let orderGroup = BudgetRuleService.OrderGroup.forPicker(from: rule.type) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            rule.subCategory = nil
            return
        }
        rule.subCategory = findOrCreate(orderGroup: orderGroup, title: trimmed, in: context)
    }

    static func assignSubCategory(
        to tile: BudgetTile,
        title: String,
        in context: ModelContext
    ) {
        guard let orderGroup = BudgetRuleService.OrderGroup.forPicker(from: tile.type) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            tile.subCategory = nil
            return
        }
        tile.subCategory = findOrCreate(orderGroup: orderGroup, title: trimmed, in: context)
    }

    // MARK: - Totals

    static func monthlyTotal(for rules: [BudgetRule]) -> Int {
        rules
            .filter { $0.isActive && !$0.isArchived }
            .map { BudgetRuleService.monthlyEquivalent(for: $0) }
            .reduce(0, +)
    }

    static func rules(
        in subCategory: BudgetRuleSubCategory,
        from allRules: [BudgetRule]
    ) -> [BudgetRule] {
        BudgetRuleService.sorted(allRules.filter { $0.subCategory?.id == subCategory.id })
    }

    static func uncategorisedRules(
        in orderGroup: BudgetRuleService.OrderGroup,
        from allRules: [BudgetRule],
        subCategories allSubCategories: [BudgetRuleSubCategory]
    ) -> [BudgetRule] {
        let groupRules = BudgetRuleService.rules(in: orderGroup, from: allRules)
        let visibleSubCategories = subCategories(for: orderGroup, from: allSubCategories)
        let categorisedIDs = Set(
            visibleSubCategories.flatMap { rules(in: $0, from: allRules).map(\.id) }
        )
        return BudgetRuleService.sorted(groupRules.filter { !categorisedIDs.contains($0.id) })
    }
}
