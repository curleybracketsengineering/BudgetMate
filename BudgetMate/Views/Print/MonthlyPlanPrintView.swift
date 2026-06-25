import SwiftUI

struct PrintableAccountOpening: Identifiable {
    let id: UUID
    let name: String
    let openingMinorUnits: Int
}

struct PrintableMonthRow: Identifiable {
    let id: UUID
    let title: String
    let opening: Int
    let income: Int
    let expense: Int
    let closing: Int
    var isLocked: Bool = false
    var accountOpenings: [PrintableAccountOpening] = []
}

enum MonthlyPlanExportRange: CaseIterable, Identifiable {
    case three
    case six
    case twelve
    case all

    var id: Self { self }

    var label: String {
        switch self {
        case .three: "3 months"
        case .six: "6 months"
        case .twelve: "12 months"
        case .all: "All"
        }
    }

    func selectedItems<T>(from items: [T]) -> [T] {
        switch self {
        case .three: Array(items.prefix(3))
        case .six: Array(items.prefix(6))
        case .twelve: Array(items.prefix(12))
        case .all: items
        }
    }

    func selectedMonths(from months: [PrintableMonthRow]) -> [PrintableMonthRow] {
        selectedItems(from: months)
    }

    func horizonLabel(from months: [PrintableMonthRow], fullHorizonLabel: String) -> String {
        let selected = selectedMonths(from: months)
        guard !selected.isEmpty else { return fullHorizonLabel }
        switch self {
        case .all:
            return fullHorizonLabel
        case .three, .six, .twelve:
            if selected.count == 1 {
                return selected[0].title
            }
            return "\(selected[0].title) – \(selected[selected.count - 1].title)"
        }
    }
}

enum MonthlyPlanPrintPaginator {
    static let columnsPerRow = 4
    static let maxRowsPerPage = 4
    static let monthsPerPage = columnsPerRow * maxRowsPerPage

    private static let landscapeContentHeight: CGFloat = 507
    private static let headerHeight: CGFloat = 36
    private static let rowSpacing: CGFloat = 6

    static func pages(
        months: [PrintableMonthRow],
        maxAccountCount: Int
    ) -> [[PrintableMonthRow]] {
        let cardHeight = estimatedCardHeight(accountLines: max(maxAccountCount, 1))
        let rowsThatFit = maxRowsThatFit(cardHeight: cardHeight)
        let capacity = rowsThatFit * columnsPerRow

        guard capacity > 0 else { return [months] }

        var chunks: [[PrintableMonthRow]] = []
        var index = 0
        while index < months.count {
            let end = min(index + capacity, months.count)
            chunks.append(Array(months[index..<end]))
            index = end
        }
        return chunks
    }

    private static func maxRowsThatFit(cardHeight: CGFloat) -> Int {
        let available = landscapeContentHeight - headerHeight
        for rows in stride(from: maxRowsPerPage, through: 1, by: -1) {
            let gridHeight = CGFloat(rows) * cardHeight + CGFloat(rows - 1) * rowSpacing
            if gridHeight <= available {
                return rows
            }
        }
        return 1
    }

    private static func estimatedCardHeight(accountLines: Int) -> CGFloat {
        let openingSection: CGFloat = accountLines > 1
            ? 8 + CGFloat(accountLines) * 8
            : 9
        return 10 + openingSection + 2 + 24 + 3 + 15
    }
}

enum MonthlyPlanPrintDocument {
    @MainActor
    static func pageViews(
        currency: AppCurrency,
        settings: AppSettings,
        months: [PrintableMonthRow],
        horizonLabel: String
    ) -> [MonthlyPlanPrintPageView] {
        let maxAccounts = months.map { max($0.accountOpenings.count, 1) }.max() ?? 1
        let chunks = MonthlyPlanPrintPaginator.pages(
            months: months,
            maxAccountCount: maxAccounts
        )
        let totalPages = chunks.count

        return chunks.enumerated().map { index, chunk in
            MonthlyPlanPrintPageView(
                currency: currency,
                settings: settings,
                months: chunk,
                pageIndex: index,
                totalPages: totalPages,
                horizonLabel: index == 0 ? horizonLabel : nil
            )
        }
    }
}

struct MonthlyPlanPrintPageView: View {
    let currency: AppCurrency
    let settings: AppSettings
    let months: [PrintableMonthRow]
    let pageIndex: Int
    let totalPages: Int
    let horizonLabel: String?

    private let gridSpacing: CGFloat = 6
    private let columnsPerRow = MonthlyPlanPrintPaginator.columnsPerRow

    private var rows: [[PrintableMonthRow]] {
        chunked(months, size: columnsPerRow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: gridSpacing) {
            header
            VStack(alignment: .leading, spacing: gridSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: gridSpacing) {
                        ForEach(row) { month in
                            PrintMonthCardView(
                                month: month,
                                currency: currency,
                                settings: settings
                            )
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        ForEach(0..<(columnsPerRow - row.count), id: \.self) { _ in
                            Spacer()
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var header: some View {
        if pageIndex == 0 {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("BudgetMate · Monthly Plan")
                        .font(PrintTypography.documentTitle)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(Date.now, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        .font(PrintTypography.documentDate)
                        .foregroundStyle(.secondary)
                }
                if let horizonLabel {
                    Text("Planning \(horizonLabel)")
                        .font(PrintTypography.metadata)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack {
                Spacer()
                Text("Page \(pageIndex + 1) of \(totalPages)")
                    .font(PrintTypography.documentDate)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chunked(_ months: [PrintableMonthRow], size: Int) -> [[PrintableMonthRow]] {
        guard size > 0 else { return [] }
        var result: [[PrintableMonthRow]] = []
        var index = 0
        while index < months.count {
            let end = min(index + size, months.count)
            result.append(Array(months[index..<end]))
            index = end
        }
        return result
    }
}

struct PrintMonthCardView: View {
    let month: PrintableMonthRow
    let currency: AppCurrency
    let settings: AppSettings

    private var hasMultipleAccounts: Bool { !month.accountOpenings.isEmpty }
    private var netMinorUnits: Int { month.income - month.expense }

    private var accentColor: Color {
        switch CashFlowService.thresholdLevel(balance: month.closing, settings: settings) {
        case .safe: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(month.title)
                    .font(PrintTypography.documentTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if month.isLocked {
                    Image(systemName: "lock.fill")
                        .font(PrintTypography.icon)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 2)

            if hasMultipleAccounts {
                accountBalanceSection
            } else {
                amountRow(label: "Opening", minorUnits: month.opening)
            }

            VStack(alignment: .leading, spacing: 0) {
                amountRow(label: "Income", minorUnits: month.income, tint: .green)
                amountRow(label: "Expenses", minorUnits: month.expense, tint: .red)
                amountRow(label: "Net", minorUnits: netMinorUnits, tint: netMinorUnits >= 0 ? .green : .red)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 5)
        .padding(.top, 5)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accentColor)
                .frame(height: 3)
        }
        .border(Color(white: 0.3), width: 1)
    }

    private var accountBalanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Opening")
                .font(PrintTypography.label)
                .foregroundStyle(.secondary)
                .padding(.bottom, 1)

            ForEach(month.accountOpenings) { account in
                amountRow(
                    label: account.name,
                    minorUnits: account.openingMinorUnits,
                    labelIndent: 3
                )
            }
        }
    }

    private func amountRow(
        label: String,
        minorUnits: Int,
        tint: Color = .primary,
        labelIndent: CGFloat = 0
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(label)
                .font(PrintTypography.label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.leading, labelIndent)

            Spacer(minLength: 2)

            Text(MoneyFormatter.format(minorUnits: minorUnits, currency: currency))
                .font(PrintTypography.amount)
                .foregroundStyle(tint == .primary ? .primary : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
