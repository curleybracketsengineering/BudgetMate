import SwiftUI

struct TileRowView: View {
    let tile: BudgetTile
    let currency: AppCurrency
    var accountName: String?
    var transferDescription: String?
    var onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 8) {
                    Text(tile.type.displayName)
                    Text("·")
                    Text(tile.source.displayName)
                    if let transferDescription {
                        Text("·")
                        Text(transferDescription)
                    } else if let accountName {
                        Text("·")
                        Text(accountName)
                    }
                    if !tile.category.isEmpty {
                        Text("·")
                        Text(tile.category)
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
