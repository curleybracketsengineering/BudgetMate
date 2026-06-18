import SwiftUI

struct GroupedTileRowView: View {
    let title: String
    let itemCount: Int
    let totalMinorUnits: Int
    let currency: AppCurrency
    let tiles: [BudgetTile]
    let hasMultipleAccounts: Bool
    let accounts: [BankAccount]
    var rulesById: [UUID: BudgetRule] = [:]
    var onEditTile: (BudgetTile) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(MoneyFormatter.format(minorUnits: totalMinorUnits, currency: currency))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.primary)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tiles, id: \.id) { tile in
                        TileRowView(
                            tile: tile,
                            currency: currency,
                            ruleCycle: tile.linkedRuleId.flatMap { rulesById[$0]?.cycle },
                            accountName: hasMultipleAccounts && tile.type != .transfer
                                ? BankAccountService.accountName(for: tile.linkedAccountId, accounts: accounts)
                                : nil,
                            transferDescription: tile.type == .transfer
                                ? BankAccountService.transferDescription(
                                    from: tile.linkedAccountId,
                                    to: tile.transferToAccountId,
                                    accounts: accounts
                                )
                                : nil
                        ) {
                            onEditTile(tile)
                        }
                        .padding(.leading, 12)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}
