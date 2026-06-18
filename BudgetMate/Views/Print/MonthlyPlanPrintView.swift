import SwiftUI

struct PrintableMonthRow: Identifiable {
    let id: UUID
    let title: String
    let opening: Int
    let income: Int
    let expense: Int
    let closing: Int
    var isLocked: Bool = false
}

struct MonthlyPlanPrintView: View {
    let currency: AppCurrency
    let months: [PrintableMonthRow]
    let horizonLabel: String

    private var trailingAlignments: [HorizontalAlignment] {
        [.leading, .trailing, .trailing, .trailing, .trailing]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Month-by-month cash flow across your planning horizon.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            PrintFootnote(text: "Planning \(horizonLabel)")

            PrintTableHeader(
                columns: ["Month", "Opening", "Income", "Expenses", "Closing"],
                alignments: trailingAlignments
            )

            ForEach(months) { month in
                PrintTableRow(
                    values: [
                        month.isLocked ? "\(month.title) (Locked)" : month.title,
                        MoneyFormatter.format(minorUnits: month.opening, currency: currency),
                        MoneyFormatter.format(minorUnits: month.income, currency: currency),
                        MoneyFormatter.format(minorUnits: month.expense, currency: currency),
                        MoneyFormatter.format(minorUnits: month.closing, currency: currency)
                    ],
                    tints: [.primary, .primary, .green, .red, .primary],
                    alignments: trailingAlignments,
                    isBold: false
                )
            }

            if let last = months.last, months.count > 1 {
                HStack {
                    Text("End of plan closing balance")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(MoneyFormatter.format(minorUnits: last.closing, currency: currency))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                .padding(.top, 8)
            }
        }
    }
}
