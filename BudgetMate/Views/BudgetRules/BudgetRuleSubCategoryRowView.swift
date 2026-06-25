import SwiftUI

struct BudgetRuleSubCategoryRowView<RuleRow: View>: View {
    let subCategory: BudgetRuleSubCategory
    let rules: [BudgetRule]
    let currency: AppCurrency
    let monthlyTotal: Int
    let scheduledOnly: Bool
    @Binding var isExpanded: Bool
    let canReorder: Bool
    let onAddNewItem: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    var onReorderRule: ((UUID, Int) -> Bool)?
    var onDropRule: ((UUID) -> Bool)?
    @ViewBuilder let ruleRow: (BudgetRule) -> RuleRow

    @State private var isDropTarget = false
    @State private var dropTargetIndex: Int?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if canReorder, let onReorderRule {
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    reorderDropZone(at: index, onReorderRule: onReorderRule)

                    ruleRow(rule)

                    if rule.id != rules.last?.id {
                        Divider()
                            .padding(.leading, 28)
                    }
                }

                if !rules.isEmpty {
                    reorderDropZone(at: rules.count, onReorderRule: onReorderRule, showsEndHint: true)
                }
            } else {
                ForEach(rules, id: \.id) { rule in
                    ruleRow(rule)
                }
            }
        } label: {
            subCategoryLabel
        }
        .disclosureGroupStyle(ProminentDisclosureGroupStyle())
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items)
        } isTargeted: { isDropTarget = $0 }
        .contextMenu {
            Button {
                onAddNewItem()
            } label: {
                Label("Add new item", systemImage: "plus")
            }
            Divider()
            Button("Rename") { onRename() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private var subCategoryLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(subCategory.title)
                    .font(.body.weight(.medium))
                Text("\(rules.count) rule\(rules.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if scheduledOnly {
                Text("On calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(MoneyFormatter.format(minorUnits: monthlyTotal, currency: currency))
                    .font(.body.weight(.medium).monospacedDigit())
                Text("/ mo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .background(
            isDropTarget ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDropTarget ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .help(canReorder ? "Drop rules here to categorise" : "")
    }

    @ViewBuilder
    private func reorderDropZone(
        at index: Int,
        onReorderRule: @escaping (UUID, Int) -> Bool,
        showsEndHint: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            if showsEndHint {
                Image(systemName: "arrow.down.circle.dashed")
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                Text("Drop to move to end")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if dropTargetIndex == index {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor)
                    .frame(height: 2)
            } else if showsEndHint {
                Spacer(minLength: 0)
            } else {
                Color.clear.frame(height: 6)
            }
        }
        .padding(.vertical, showsEndHint ? 4 : 0)
        .listRowInsets(EdgeInsets(top: 0, leading: 28, bottom: 0, trailing: 8))
        .dropDestination(for: String.self) { items, _ in
            handleReorderDrop(items, at: index, onReorderRule: onReorderRule)
        } isTargeted: { targeted in
            if targeted {
                dropTargetIndex = index
            } else if dropTargetIndex == index {
                dropTargetIndex = nil
            }
        }
    }

    private func handleDrop(_ items: [String]) -> Bool {
        guard canReorder, let onDropRule, let payload = items.first,
              let ruleID = UUID(uuidString: payload) else {
            return false
        }
        return onDropRule(ruleID)
    }

    private func handleReorderDrop(
        _ items: [String],
        at index: Int,
        onReorderRule: (UUID, Int) -> Bool
    ) -> Bool {
        guard let payload = items.first, let ruleID = UUID(uuidString: payload) else {
            return false
        }
        return onReorderRule(ruleID, index)
    }
}

private struct ProminentDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.8))
                        .frame(width: 18)
                    configuration.label
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}
