import Foundation
import SwiftData

@Model
final class BudgetRuleSubCategory {
    var id: UUID = UUID()
    var title: String = ""
    var orderGroupRaw: String = ""
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \BudgetRule.subCategory)
    var rules: [BudgetRule] = []

    init(title: String = "", orderGroup: BudgetRuleService.OrderGroup = .outgoing, sortOrder: Int = 0) {
        self.title = title
        self.orderGroupRaw = orderGroup.rawValue
        self.sortOrder = sortOrder
    }

    var orderGroup: BudgetRuleService.OrderGroup {
        get { BudgetRuleService.OrderGroup(rawValue: orderGroupRaw) ?? .outgoing }
        set { orderGroupRaw = newValue.rawValue }
    }
}

extension BudgetRuleService.OrderGroup {
    var rawValue: String {
        switch self {
        case .incoming: "incoming"
        case .outgoing: "outgoing"
        case .other: "other"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "incoming": self = .incoming
        case "outgoing": self = .outgoing
        case "other": self = .other
        default: return nil
        }
    }
}
