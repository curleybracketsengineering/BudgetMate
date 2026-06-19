import SwiftUI

struct TileRowView: View {
    let tile: BudgetTile
    let currency: AppCurrency
    var ruleCycle: BudgetCycleType?
    var accountName: String?
    var transferDescription: String?
    var onEdit: () -> Void

    private var sourceLabel: String {
        if ruleCycle == .oneOff { return "One-off" }
        return tile.source.displayName
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 8) {
                    Text(tile.type.displayName)
                    Text("·")
                    Text(sourceLabel)
                    if let transferDescription {
                        Text("·")
                        Text(transferDescription)
                    } else if let accountName {
                        Text("·")
                        Text(accountName)
                    }
                    if let title = tile.subCategory?.title, !title.isEmpty {
                        Text("·")
                        Text(title)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(MoneyFormatter.format(minorUnits: tile.amountMinorUnits, currency: currency))
                .font(.body.monospacedDigit())
            Button("Edit", action: onEdit)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
