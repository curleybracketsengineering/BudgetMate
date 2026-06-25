import SwiftUI

struct PrintableAccountBalance: Identifiable {
    let id: UUID
    let name: String
    let balance: Int
    var isPrimary: Bool = false
    var thresholdLabel: String?
}

struct PrintableForecastMonth: Identifiable {
    let id: String
    let label: String
    let balancesByAccount: [UUID: Int]
}

struct DashboardPrintView: View {
    let currency: AppCurrency
    let accounts: [PrintableAccountBalance]
    let endOfPlanLabel: String?
    let endOfPlanBalance: Int?
    let forecastMonths: [PrintableForecastMonth]
    let accountNames: [UUID: String]

    private var forecastAccountIDs: [UUID] {
        var seen = Set<UUID>()
        var ordered: [UUID] = []
        for account in accounts {
            if seen.insert(account.id).inserted {
                ordered.append(account.id)
            }
        }
        for month in forecastMonths {
            for accountId in month.balancesByAccount.keys where seen.insert(accountId).inserted {
                ordered.append(accountId)
            }
        }
        return ordered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            accountSection
            if !forecastMonths.isEmpty {
                forecastSection
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account balances")
                .font(PrintTypography.sectionTitle)

            if accounts.isEmpty {
                Text("No accounts configured.")
                    .font(PrintTypography.body)
                    .foregroundStyle(.secondary)
            } else {
                PrintTableHeader(
                    columns: ["Account", "Current balance", "Status"],
                    alignments: [.leading, .trailing, .trailing]
                )

                ForEach(accounts) { account in
                    PrintTableRow(
                        values: [
                            account.isPrimary ? "\(account.name) (Primary)" : account.name,
                            MoneyFormatter.format(minorUnits: account.balance, currency: currency),
                            account.thresholdLabel ?? "—"
                        ],
                        tints: [.primary, thresholdTint(for: account.thresholdLabel), .secondary],
                        alignments: [.leading, .trailing, .trailing]
                    )
                }

                if let endOfPlanLabel, let endOfPlanBalance {
                    HStack {
                        Text("End of plan (\(endOfPlanLabel))")
                            .font(PrintTypography.bodySemibold)
                        Spacer()
                        Text(MoneyFormatter.format(minorUnits: endOfPlanBalance, currency: currency))
                            .font(PrintTypography.amountSemibold)
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    private var forecastSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Forecast")
                .font(PrintTypography.sectionTitle)

            Text("Projected closing balance by month.")
                .font(PrintTypography.body)
                .foregroundStyle(.secondary)

            let accountIDs = forecastAccountIDs
            let columns = ["Month"] + accountIDs.map { accountNames[$0] ?? "Account" }
            let alignments = [HorizontalAlignment.leading] + Array(repeating: HorizontalAlignment.trailing, count: accountIDs.count)

            PrintTableHeader(columns: columns, alignments: alignments)

            ForEach(forecastMonths) { month in
                let values = [month.label] + accountIDs.map { accountId in
                    guard let balance = month.balancesByAccount[accountId] else { return "—" }
                    return MoneyFormatter.format(minorUnits: balance, currency: currency)
                }
                PrintTableRow(values: values, alignments: alignments)
            }
        }
    }

    private func thresholdTint(for label: String?) -> Color {
        switch label {
        case "Safe": .green
        case "Warning": .orange
        case "Critical": .red
        default: .primary
        }
    }
}
