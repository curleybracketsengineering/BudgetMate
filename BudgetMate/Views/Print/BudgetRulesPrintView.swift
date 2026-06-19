import SwiftUI

struct PrintableBudgetRuleRow: Identifiable {
    let id: UUID
    let name: String
    let metadata: String
    let amount: String
    var badge: String?
}

struct PrintableBudgetRuleSubCategoryGroup: Identifiable {
    let id: UUID
    let title: String
    let subtotal: String
    let rows: [PrintableBudgetRuleRow]
}

struct PrintableBudgetRuleSectionContent {
    var groups: [PrintableBudgetRuleSubCategoryGroup] = []
    var ungrouped: [PrintableBudgetRuleRow] = []

    var isEmpty: Bool {
        groups.isEmpty && ungrouped.isEmpty
    }
}

struct BudgetRulesPrintView: View {
    let summary: BudgetRuleService.Summary
    let currency: AppCurrency
    let incoming: PrintableBudgetRuleSectionContent
    let outgoing: PrintableBudgetRuleSectionContent
    let other: [PrintableBudgetRuleRow]
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recurring income and expenses that generate tiles in your monthly plan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            summarySection

            if let footnote {
                PrintFootnote(text: footnote)
            }

            if !incoming.isEmpty {
                groupedRuleSection(title: "Incoming", content: incoming)
            }

            if !outgoing.isEmpty {
                groupedRuleSection(title: "Outgoing", content: outgoing)
            }

            if !other.isEmpty {
                ruleSection(title: "Other", rules: other)
            }
        }
    }

    @ViewBuilder
    private func groupedRuleSection(title: String, content: PrintableBudgetRuleSectionContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PrintSectionHeader(title: title)
            ForEach(content.groups) { group in
                HStack {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(group.subtotal)
                        .font(.subheadline.monospacedDigit())
                }
                .padding(.vertical, 4)
                ForEach(group.rows) { rule in
                    PrintRuleRow(
                        name: rule.name,
                        metadata: rule.metadata,
                        amount: rule.amount,
                        badge: rule.badge
                    )
                    .padding(.leading, 12)
                }
            }
            if !content.ungrouped.isEmpty {
                if !content.groups.isEmpty {
                    Text("Uncategorised")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                ForEach(content.ungrouped) { rule in
                    PrintRuleRow(
                        name: rule.name,
                        metadata: rule.metadata,
                        amount: rule.amount,
                        badge: rule.badge
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func ruleSection(title: String, rules: [PrintableBudgetRuleRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PrintSectionHeader(title: title)
            ForEach(rules) { rule in
                PrintRuleRow(
                    name: rule.name,
                    metadata: rule.metadata,
                    amount: rule.amount,
                    badge: rule.badge
                )
            }
        }
    }

    private var summarySection: some View {
        PrintSummaryGrid(items: summaryItems)
    }

    private var summaryItems: [PrintSummaryItem] {
        var items: [PrintSummaryItem] = [
            PrintSummaryItem(title: "Active rules", value: "\(summary.activeCount)"),
            PrintSummaryItem(
                title: "Income / month",
                value: MoneyFormatter.format(minorUnits: summary.incomeMinorUnits, currency: currency),
                tint: .green
            ),
            PrintSummaryItem(
                title: "Bills / month",
                value: MoneyFormatter.format(minorUnits: summary.expenseMinorUnits, currency: currency),
                tint: .red
            )
        ]

        if summary.savingMinorUnits > 0 {
            items.append(PrintSummaryItem(
                title: "Savings / month",
                value: MoneyFormatter.format(minorUnits: summary.savingMinorUnits, currency: currency)
            ))
        }

        items.append(PrintSummaryItem(
            title: "Net / month",
            value: MoneyFormatter.format(minorUnits: summary.netMinorUnits, currency: currency),
            tint: summary.netMinorUnits >= 0 ? .green : .red
        ))

        return items
    }
}
