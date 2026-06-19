import Foundation

struct BankTransactionRow: Identifiable, Hashable {
    let id: UUID
    let referenceNumber: String
    let date: Date
    let account: String
    let signedAmountMinorUnits: Int
    let subcategory: String
    let payee: String
    let memo: String

    init(
        id: UUID = UUID(),
        referenceNumber: String,
        date: Date,
        account: String,
        signedAmountMinorUnits: Int,
        subcategory: String,
        payee: String,
        memo: String
    ) {
        self.id = id
        self.referenceNumber = referenceNumber
        self.date = date
        self.account = account
        self.signedAmountMinorUnits = signedAmountMinorUnits
        self.subcategory = subcategory
        self.payee = payee
        self.memo = memo
    }

    var year: Int {
        Calendar.current.component(.year, from: date)
    }

    var month: Int {
        Calendar.current.component(.month, from: date)
    }

    var amountMinorUnits: Int {
        abs(signedAmountMinorUnits)
    }

    var isInflow: Bool {
        signedAmountMinorUnits > 0
    }
}

struct ImportPreviewRow: Identifiable {
    let id: UUID
    var transaction: BankTransactionRow
    var budgetType: BudgetType
    var suggestedSubCategoryTitle: String

    init(transaction: BankTransactionRow, budgetType: BudgetType, suggestedSubCategoryTitle: String) {
        self.id = transaction.id
        self.transaction = transaction
        self.budgetType = budgetType
        self.suggestedSubCategoryTitle = suggestedSubCategoryTitle
    }
}
