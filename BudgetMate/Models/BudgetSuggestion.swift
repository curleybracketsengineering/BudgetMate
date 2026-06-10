import Foundation

struct BudgetSuggestion: Identifiable, Hashable {
    let id: UUID
    var name: String
    var budgetType: BudgetType
    var category: String
    var cycle: BudgetCycleType
    /// Amount per occurrence (what appears on each payment).
    var amountMinorUnits: Int
    /// Typical monthly impact across a full year.
    var monthlyEquivalentMinorUnits: Int
    var activeMonths: [Int]
    var startDate: Date
    var confidence: ConfidenceLevel
    var explanation: String
    var paymentMethod: String
    var amountMinMinorUnits: Int
    var amountMaxMinorUnits: Int
    var transactionCount: Int
    var linkedTransactionIDs: Set<UUID>
    var isAccepted: Bool
    var isIgnored: Bool
    var payeeMatchKey: String
    var userNotes: String
    var bankPayeeSample: String

    init(
        id: UUID = UUID(),
        name: String,
        budgetType: BudgetType,
        category: String,
        cycle: BudgetCycleType,
        amountMinorUnits: Int,
        monthlyEquivalentMinorUnits: Int,
        activeMonths: [Int] = [],
        startDate: Date,
        confidence: ConfidenceLevel,
        explanation: String,
        paymentMethod: String = "Other",
        amountMinMinorUnits: Int? = nil,
        amountMaxMinorUnits: Int? = nil,
        transactionCount: Int,
        linkedTransactionIDs: Set<UUID>,
        isAccepted: Bool = false,
        isIgnored: Bool = false,
        payeeMatchKey: String = "",
        userNotes: String = "",
        bankPayeeSample: String = ""
    ) {
        self.id = id
        self.name = name
        self.budgetType = budgetType
        self.category = category
        self.cycle = cycle
        self.amountMinorUnits = amountMinorUnits
        self.monthlyEquivalentMinorUnits = monthlyEquivalentMinorUnits
        self.activeMonths = activeMonths
        self.startDate = startDate
        self.confidence = confidence
        self.explanation = explanation
        self.paymentMethod = paymentMethod
        self.amountMinMinorUnits = amountMinMinorUnits ?? amountMinorUnits
        self.amountMaxMinorUnits = amountMaxMinorUnits ?? amountMinorUnits
        self.transactionCount = transactionCount
        self.linkedTransactionIDs = linkedTransactionIDs
        self.isAccepted = isAccepted
        self.isIgnored = isIgnored
        self.payeeMatchKey = payeeMatchKey
        self.userNotes = userNotes
        self.bankPayeeSample = bankPayeeSample
    }

    var monthPatternRaw: String {
        activeMonths.map(String.init).joined(separator: ",")
    }

    var hasAmountVariance: Bool {
        amountMinMinorUnits != amountMaxMinorUnits
    }
}

struct TypicalMonthSummary {
    var incomeMinorUnits: Int = 0
    var expenseMinorUnits: Int = 0
    var savingMinorUnits: Int = 0
    var transferMinorUnits: Int = 0
    var flexibleSpendingMinorUnits: Int = 0
    var suggestionCount: Int = 0
    var analysisMonthCount: Int = 0
}
