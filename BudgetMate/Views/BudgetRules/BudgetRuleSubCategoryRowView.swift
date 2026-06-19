import SwiftUI

struct BudgetRuleSubCategoryRowView<RuleRow: View>: View {
    let subCategory: BudgetRuleSubCategory
    let rules: [BudgetRule]
    let currency: AppCurrency
    let monthlyTotal: Int
    @Binding var isExpanded: Bool
    let canReorder: Bool
    let onRename: () -> Void
    let onDelete: () -> Void
    var onMoveRules: ((IndexSet, Int) -> Void)?
    @ViewBuilder let ruleRow: (BudgetRule) -> RuleRow

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if canReorder, let onMoveRules {
                ForEach(rules, id: \.id) { rule in
                    ruleRow(rule)
                }
                .onMove(perform: onMoveRules)
            } else {
                ForEach(rules, id: \.id) { rule in
                    ruleRow(rule)
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(subCategory.title)
                        .font(.body.weight(.medium))
                    Text("\(rules.count) rule\(rules.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(MoneyFormatter.format(minorUnits: monthlyTotal, currency: currency))
                    .font(.body.weight(.medium).monospacedDigit())
                Text("/ mo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Rename") { onRename() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}
