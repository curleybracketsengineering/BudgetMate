import SwiftUI

struct RulePreviewPanel: View {
    let rule: BudgetRule
    let currency: AppCurrency
    var accountName: String?
    var transferDescription: String?
    var linkedTileCount: Int = 0
    var showExpiryWarning: Bool = false
    var onRestore: (() -> Void)?
    var onDeletePermanently: (() -> Void)?

    private var monthlyEquivalent: Int {
        BudgetRuleService.monthlyEquivalent(for: rule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(rule.name)
                    .font(.title3.weight(.semibold))
                Spacer()
                statusBadges
            }

            if showExpiryWarning, let endDate = rule.endDate {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Ends \(endDate.formatted(date: .abbreviated, time: .omitted))")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Type").foregroundStyle(.secondary)
                    Text(rule.type.displayName)
                }
                GridRow {
                    Text("Amount").foregroundStyle(.secondary)
                    Text(MoneyFormatter.format(minorUnits: rule.amountMinorUnits, currency: currency))
                }
                GridRow {
                    Text("Per month").foregroundStyle(.secondary)
                    Text(MoneyFormatter.format(minorUnits: monthlyEquivalent, currency: currency))
                        .foregroundStyle(rule.type == .income ? .green : .primary)
                }
                GridRow {
                    Text("Cycle").foregroundStyle(.secondary)
                    Text(rule.cycle.displayName)
                }
                if rule.cycle == .tenMonthly, !rule.monthPatternRaw.isEmpty {
                    GridRow {
                        Text("Months").foregroundStyle(.secondary)
                        Text(BudgetRuleService.formatMonthPatternDisplay(rule.monthPatternRaw))
                    }
                }
                GridRow {
                    Text("Category").foregroundStyle(.secondary)
                    Text(rule.category.isEmpty ? "—" : rule.category)
                }
                if let transferDescription {
                    GridRow {
                        Text("Transfer").foregroundStyle(.secondary)
                        Text(transferDescription)
                    }
                } else if let accountName {
                    GridRow {
                        Text("Account").foregroundStyle(.secondary)
                        Text(accountName)
                    }
                }
                GridRow {
                    Text("Commitment").foregroundStyle(.secondary)
                    Text(rule.commitment.displayName)
                }
                GridRow {
                    Text("Start").foregroundStyle(.secondary)
                    Text(rule.startDate.formatted(date: .abbreviated, time: .omitted))
                }
                if let end = rule.endDate {
                    GridRow {
                        Text("End").foregroundStyle(.secondary)
                        Text(end.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                GridRow {
                    Text("Confidence").foregroundStyle(.secondary)
                    Text(rule.confidence.displayName)
                }
                if linkedTileCount > 0 {
                    GridRow {
                        Text("Tiles").foregroundStyle(.secondary)
                        Text("\(linkedTileCount) in plan")
                    }
                }
            }
            .font(.subheadline)

            if !rule.assumptionsNotes.isEmpty {
                Divider()
                Text("Assumptions")
                    .font(.subheadline.weight(.semibold))
                Text(rule.assumptionsNotes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if rule.isArchived {
                Divider()
                HStack(spacing: 10) {
                    if let onRestore {
                        Button {
                            onRestore()
                        } label: {
                            Label("Restore from archive", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                    }
                    if let onDeletePermanently {
                        Button(role: .destructive) {
                            onDeletePermanently()
                        } label: {
                            Label("Delete permanently", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var statusBadges: some View {
        HStack(spacing: 6) {
            if rule.isArchived {
                badge("Archived", color: .secondary)
            } else if !rule.isActive {
                badge("Paused", color: .orange)
            } else {
                badge("Active", color: .green)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
