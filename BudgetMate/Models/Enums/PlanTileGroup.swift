import Foundation

/// How recurring tiles are rolled up in the monthly plan view.
enum PlanTileGroup: String, CaseIterable, Identifiable {
    case incomeEveryFourWeeks
    case income
    case outgoings

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .incomeEveryFourWeeks: "Income (every 4 weeks)"
        case .income: "Income"
        case .outgoings: "Outgoings"
        }
    }

    var sortOrder: Int {
        switch self {
        case .incomeEveryFourWeeks: 0
        case .income: 1
        case .outgoings: 2
        }
    }

    static func forTile(_ tile: BudgetTile, rule: BudgetRule?) -> PlanTileGroup? {
        guard !showsIndividually(tile: tile, rule: rule) else { return nil }

        switch tile.type {
        case .income:
            if rule?.cycle == .everyFourWeeks {
                return .incomeEveryFourWeeks
            }
            return .income
        case .expense, .saving:
            return .outgoings
        case .transfer, .adjustment:
            return nil
        }
    }

    static func showsIndividually(tile: BudgetTile, rule: BudgetRule?) -> Bool {
        if let rule, tile.linkedRuleId == rule.id {
            return rule.showIndividuallyInPlan
        }
        return true
    }
}

struct PlanTileDisplaySection: Identifiable {
    enum Kind {
        case grouped(PlanTileGroup)
        case individual
    }

    let kind: Kind
    let title: String
    let tiles: [BudgetTile]
    let totalMinorUnits: Int

    var id: String {
        switch kind {
        case .grouped(let group): "group-\(group.rawValue)"
        case .individual: "individual"
        }
    }

    var isGrouped: Bool {
        if case .grouped = kind { return true }
        return false
    }
}

enum PlanTileGroupingService {
    static func displaySections(
        tiles: [BudgetTile],
        rules: [BudgetRule]
    ) -> [PlanTileDisplaySection] {
        let rulesById = rules.keyedById()
        var grouped: [PlanTileGroup: [BudgetTile]] = [:]
        var individual: [BudgetTile] = []

        for tile in tiles {
            let rule = tile.linkedRuleId.flatMap { rulesById[$0] }
            if let group = PlanTileGroup.forTile(tile, rule: rule) {
                grouped[group, default: []].append(tile)
            } else {
                individual.append(tile)
            }
        }

        var sections: [PlanTileDisplaySection] = PlanTileGroup.allCases.compactMap { group in
            guard let groupTiles = grouped[group], !groupTiles.isEmpty else { return nil }
            let sortedTiles = sortTiles(groupTiles, rulesById: rulesById)
            let total = sortedTiles.reduce(0) { $0 + $1.amountMinorUnits }
            return PlanTileDisplaySection(
                kind: .grouped(group),
                title: group.displayName,
                tiles: sortedTiles,
                totalMinorUnits: total
            )
        }

        if !individual.isEmpty {
            let sortedIndividual = sortTiles(individual, rulesById: rulesById)
            sections.append(
                PlanTileDisplaySection(
                    kind: .individual,
                    title: "Individual items",
                    tiles: sortedIndividual,
                    totalMinorUnits: sortedIndividual.reduce(0) { $0 + $1.amountMinorUnits }
                )
            )
        }

        return sections
    }

    private static func sortTiles(_ tiles: [BudgetTile], rulesById: [UUID: BudgetRule]) -> [BudgetTile] {
        tiles.sorted { lhs, rhs in
            let lhsOrder = lhs.linkedRuleId.flatMap { rulesById[$0]?.displayOrder } ?? Int.max
            let rhsOrder = rhs.linkedRuleId.flatMap { rulesById[$0]?.displayOrder } ?? Int.max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
