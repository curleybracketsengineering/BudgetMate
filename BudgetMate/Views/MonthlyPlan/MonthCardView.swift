import SwiftUI

struct MonthCardView: View {
    let month: BudgetMonth
    let settings: AppSettings
    let income: Int
    let expense: Int
    var isSelected: Bool = false

    private var currency: AppCurrency { settings.currency }
    private var level: BalanceThresholdLevel {
        CashFlowService.thresholdLevel(balance: month.closingBalanceMinorUnits, settings: settings)
    }

    private var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }

    private var accentColor: Color {
        switch level {
        case .safe: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(month.displayTitle)
                    .font(.headline)
                Spacer()
                if month.isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }

            row("Opening", month.openingBalanceMinorUnits)
            row("Income", income, tint: .green)
            row("Expenses", expense, tint: .red)
            Divider()
            row("Closing", month.closingBalanceMinorUnits, bold: true)

            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(height: 4)
        }
        .padding()
        .background(isSelected ? Color.accentColor.opacity(0.1) : cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private func row(_ label: String, _ minorUnits: Int, tint: Color = .primary, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(MoneyFormatter.format(minorUnits: minorUnits, currency: currency))
                .font(bold ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(tint == .primary ? .primary : tint)
        }
    }
}
