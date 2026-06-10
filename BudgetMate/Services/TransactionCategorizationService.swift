import Foundation

enum TransactionCategorizationService {
    static func previewRows(from transactions: [BankTransactionRow]) -> [ImportPreviewRow] {
        transactions.map { transaction in
            let classification = classify(transaction)
            return ImportPreviewRow(
                transaction: transaction,
                budgetType: classification.type,
                category: classification.category
            )
        }
    }

    static func classify(_ transaction: BankTransactionRow) -> (type: BudgetType, category: String) {
        let payee = transaction.payee.uppercased()
        let memo = transaction.memo.uppercased()
        let combined = "\(payee) \(memo)"

        if isSavingTransfer(combined) {
            return (.saving, "Savings")
        }

        if isInternalTransfer(transaction.subcategory, combined: combined) {
            return (.transfer, "Transfers")
        }

        switch transaction.subcategory {
        case "Direct Debit":
            return (.expense, categoryForPayee(payee, defaultCategory: "Bills"))
        case "Standing Order":
            return standingOrderClassification(payee: payee, combined: combined)
        case "Debit", "Card Purchase":
            return (.expense, "Spending")
        case "Counter Credit":
            return (.income, incomeCategory(payee: payee))
        case "Transfer":
            return transaction.isInflow
                ? (.income, incomeCategory(payee: payee))
                : (.transfer, "Transfers")
        case "Credit":
            return (.income, "Refunds")
        case "Bill Payment":
            return (.transfer, "Card payments")
        case "Funds Transfer":
            return fundsTransferClassification(combined: combined, isInflow: transaction.isInflow)
        default:
            return transaction.isInflow
                ? (.income, "Income")
                : (.expense, "Spending")
        }
    }

    private static func standingOrderClassification(payee: String, combined: String) -> (BudgetType, String) {
        if combined.contains("SAVINGS") || combined.contains("SAVER") {
            return (.saving, "Savings")
        }
        if combined.contains("EXPENSESS") {
            return (.expense, "Household")
        }
        return (.expense, categoryForPayee(payee, defaultCategory: "Bills"))
    }

    private static func fundsTransferClassification(combined: String, isInflow: Bool) -> (BudgetType, String) {
        if isInflow {
            return (.transfer, "Transfers")
        }
        if combined.contains("PENSION") {
            return (.saving, "Pension")
        }
        if combined.contains("SAVINGS") || combined.contains("SAVER") {
            return (.saving, "Savings")
        }
        return (.transfer, "Transfers")
    }

    private static func isSavingTransfer(_ combined: String) -> Bool {
        combined.contains("BODHI SAVINGS")
            || combined.contains("EVERYDAY SAVER")
            || combined.contains("PENSION OVER TAX")
    }

    private static func isInternalTransfer(_ subcategory: String, combined: String) -> Bool {
        subcategory == "Funds Transfer" && (
            combined.contains("OPENPLAN")
                || combined.contains("MOBILE-CHANNEL")
                || combined.contains("MR SCOTT MATHESON")
        )
    }

    private static func incomeCategory(payee: String) -> String {
        if payee.contains("PENSION") || payee.contains("ORACLE") || payee.contains("COLSTON") || payee.contains("SEB") {
            return "Pension"
        }
        if payee.contains("DWP") || payee.contains("FORSAKRINGSKASSA") {
            return "Pension"
        }
        if payee.contains("BGC") || payee.contains("LTD") || payee.contains("IVALUA") {
            return "Salary"
        }
        return "Income"
    }

    private static func categoryForPayee(_ payee: String, defaultCategory: String) -> String {
        if payee.contains("MORTG") || payee.contains("MTGES") || payee.contains("BARCLAYS UK") {
            return "Mortgage"
        }
        if payee.contains("ENERGY") || payee.contains("OCTOPUS") || payee.contains("WATER") {
            return "Utilities"
        }
        if payee.contains("INSURANCE") || payee.contains("ADMIRAL") || payee.contains("L&G") {
            return "Insurance"
        }
        if payee.contains("COUNCIL") || payee.contains("DVLA") || payee.contains("TV LICENCE") {
            return "Bills"
        }
        if payee.contains("SKY") || payee.contains("O2") || payee.contains("BT GROUP") {
            return "Subscriptions"
        }
        return defaultCategory
    }

    static func isKnownRegularIncomePayee(_ payee: String) -> Bool {
        let payee = payee.uppercased()
        if payee.contains("FORSAKRINGSKASSA") { return true }
        if payee.contains("SEB PENSION") { return true }
        if payee.contains("ORACLE UK PENSION") || payee.contains("ORACLE UK") { return true }
        if payee.contains("DWP") { return true }
        if payee.contains("IVALUA") { return true }
        if payee.contains("BGC") && payee.contains("PENSION") { return true }
        return false
    }
}
