import SwiftUI

struct CreateBudgetRulesConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let suggestions: [BudgetSuggestion]
    let currency: AppCurrency
    let onConfirm: () -> Void

    private var linkedTransactionCount: Int {
        suggestions.reduce(0) { $0 + $1.transactionCount }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                consequencesSection
                    .padding()

                Divider()

                rulesList
            }
            .navigationTitle("Save budget rules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save \(suggestions.count) rules") {
                        onConfirm()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private var consequencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You are about to add recurring rules to your budget. This is saved permanently — it does not happen automatically when you import a file.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                consequenceRow(
                    systemImage: "arrow.triangle.2.circlepath",
                    text: "\(suggestions.count) rule\(suggestions.count == 1 ? "" : "s") added to **Budget Rules**"
                )
                consequenceRow(
                    systemImage: "calendar",
                    text: "Forecast tiles generated across your planning horizon"
                )
                if linkedTransactionCount > 0 {
                    consequenceRow(
                        systemImage: "xmark.circle",
                        text: "\(linkedTransactionCount) linked transaction\(linkedTransactionCount == 1 ? "" : "s") moved to **Excluded** (not imported as one-off tiles)"
                    )
                }
            }
            .font(.subheadline)
        }
    }

    private var rulesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                confirmationRowHeader
                Divider()
                ForEach(suggestions) { suggestion in
                    confirmationRow(suggestion)
                    Divider()
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            .padding()
        }
    }

    private var confirmationRowHeader: some View {
        HStack(spacing: 10) {
            Text("Rule")
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
            Text("Cycle")
                .frame(width: 100, alignment: .leading)
            Text("Payment")
                .frame(width: 100, alignment: .trailing)
            Text("Txns")
                .frame(width: 40, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func confirmationRow(_ suggestion: BudgetSuggestion) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if !suggestion.category.isEmpty {
                    Text(suggestion.category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

            Text(suggestion.cycle.displayName)
                .font(.caption)
                .frame(width: 100, alignment: .leading)
                .lineLimit(2)

            Text(MoneyFormatter.format(minorUnits: suggestion.amountMinorUnits, currency: currency))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(suggestion.budgetType == .income ? .green : .primary)
                .frame(width: 100, alignment: .trailing)

            Text("\(suggestion.transactionCount)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func consequenceRow(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(LocalizedStringKey(text))
        }
    }

}
