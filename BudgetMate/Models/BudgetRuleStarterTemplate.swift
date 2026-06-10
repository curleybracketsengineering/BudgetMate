import Foundation

struct BudgetRuleStarterTemplate: Identifiable {
    let id: String
    let name: String
    let type: BudgetType
    let category: String
    let cycle: BudgetCycleType
    let commitment: CommitmentType
    let confidence: ConfidenceLevel
    let monthPatternRaw: String
    let systemImage: String

    static let all: [BudgetRuleStarterTemplate] = [
        BudgetRuleStarterTemplate(
            id: "salary",
            name: "Salary",
            type: .income,
            category: "Income",
            cycle: .monthly,
            commitment: .known,
            confidence: .known,
            monthPatternRaw: "",
            systemImage: "banknote"
        ),
        BudgetRuleStarterTemplate(
            id: "rent",
            name: "Rent / mortgage",
            type: .expense,
            category: "Housing",
            cycle: .monthly,
            commitment: .known,
            confidence: .known,
            monthPatternRaw: "",
            systemImage: "house"
        ),
        BudgetRuleStarterTemplate(
            id: "council-tax",
            name: "Council tax",
            type: .expense,
            category: "Bills",
            cycle: .tenMonthly,
            commitment: .known,
            confidence: .known,
            monthPatternRaw: "4,5,6,7,8,9,10,11,12,1",
            systemImage: "building.columns"
        ),
        BudgetRuleStarterTemplate(
            id: "utilities",
            name: "Utilities",
            type: .expense,
            category: "Bills",
            cycle: .monthly,
            commitment: .known,
            confidence: .estimated,
            monthPatternRaw: "",
            systemImage: "bolt"
        ),
        BudgetRuleStarterTemplate(
            id: "savings",
            name: "Savings transfer",
            type: .saving,
            category: "Savings",
            cycle: .monthly,
            commitment: .known,
            confidence: .known,
            monthPatternRaw: "",
            systemImage: "arrow.down.circle"
        ),
        BudgetRuleStarterTemplate(
            id: "account-transfer",
            name: "Account transfer",
            type: .transfer,
            category: "Transfer",
            cycle: .monthly,
            commitment: .known,
            confidence: .known,
            monthPatternRaw: "",
            systemImage: "arrow.left.arrow.right"
        ),
    ]
}
