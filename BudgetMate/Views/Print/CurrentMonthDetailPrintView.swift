import SwiftUI

struct PrintableMonthTileRow: Identifiable {
    let id: UUID
    let name: String
    let metadata: String
    let amountMinorUnits: Int
}

struct PrintableMonthTileSection: Identifiable {
    let id: String
    let title: String
    let totalMinorUnits: Int
    let rows: [PrintableMonthTileRow]
}

struct PrintableMonthAccountBalance: Identifiable {
    let id: UUID
    let name: String
    let openingMinorUnits: Int
}

struct PrintableMonthDetail {
    let title: String
    let isLocked: Bool
    let openingMinorUnits: Int
    let incomeMinorUnits: Int
    let expenseMinorUnits: Int
    let savingMinorUnits: Int
    let accountBalances: [PrintableMonthAccountBalance]
    let sections: [PrintableMonthTileSection]
}

enum MonthDetailPrintDocument {
    static func build(
        month: BudgetMonth,
        tiles: [BudgetTile],
        rules: [BudgetRule],
        accounts: [BankAccount],
        settings: AppSettings
    ) -> PrintableMonthDetail {
        let monthTiles = CashFlowService.tilesForMonth(year: month.year, month: month.month, from: tiles)
        let totals = CashFlowService.totals(for: monthTiles)
        let rulesById = rules.keyedById()
        let hasMultipleAccounts = accounts.count > 1
        let accountMonthBalances = CashFlowService.accountBalances(
            for: month,
            accounts: accounts,
            tiles: tiles,
            settings: settings
        )

        let openingMinorUnits: Int
        if hasMultipleAccounts, !accountMonthBalances.isEmpty {
            openingMinorUnits = accountMonthBalances.reduce(0) { $0 + $1.openingBalanceMinorUnits }
        } else {
            openingMinorUnits = month.openingBalanceMinorUnits
        }

        let accountBalances: [PrintableMonthAccountBalance] = hasMultipleAccounts
            ? accounts.compactMap { account in
                guard let balance = accountMonthBalances.first(where: { $0.accountId == account.id }) else {
                    return nil
                }
                return PrintableMonthAccountBalance(
                    id: account.id,
                    name: account.name,
                    openingMinorUnits: balance.openingBalanceMinorUnits
                )
            }
            : []

        let displaySections = PlanTileGroupingService.displaySections(tiles: monthTiles, rules: rules)
        let sections = displaySections.map { section in
            PrintableMonthTileSection(
                id: section.id,
                title: section.title,
                totalMinorUnits: section.totalMinorUnits,
                rows: section.tiles.map { tile in
                    PrintableMonthTileRow(
                        id: tile.id,
                        name: tile.name,
                        metadata: tileMetadata(
                            tile: tile,
                            rule: tile.linkedRuleId.flatMap { rulesById[$0] },
                            hasMultipleAccounts: hasMultipleAccounts,
                            accounts: accounts
                        ),
                        amountMinorUnits: tile.amountMinorUnits
                    )
                }
            )
        }

        return PrintableMonthDetail(
            title: month.displayTitle,
            isLocked: month.isLocked,
            openingMinorUnits: openingMinorUnits,
            incomeMinorUnits: totals.income,
            expenseMinorUnits: totals.expense,
            savingMinorUnits: totals.saving,
            accountBalances: accountBalances,
            sections: sections
        )
    }

    private static func tileMetadata(
        tile: BudgetTile,
        rule: BudgetRule?,
        hasMultipleAccounts: Bool,
        accounts: [BankAccount]
    ) -> String {
        let sourceLabel = rule?.cycle == .oneOff ? "One-off" : tile.source.displayName
        var parts = [tile.type.displayName, sourceLabel]

        if tile.type == .transfer {
            if let transfer = BankAccountService.transferDescription(
                from: tile.linkedAccountId,
                to: tile.transferToAccountId,
                accounts: accounts
            ) {
                parts.append(transfer)
            }
        } else if hasMultipleAccounts {
            parts.append(BankAccountService.accountName(for: tile.linkedAccountId, accounts: accounts))
        }

        if let title = tile.subCategory?.title, !title.isEmpty {
            parts.append(title)
        }

        return parts.joined(separator: " · ")
    }
}

struct CurrentMonthDetailPrintView: View {
    let currency: AppCurrency
    let detail: PrintableMonthDetail

    private let rowSpacing: CGFloat = 1
    private let sectionSpacing: CGFloat = 5
    private let twoColumnRowThreshold = 14

    private var incomeSections: [PrintableMonthTileSection] {
        detail.sections.filter { $0.id != "group-outgoings" }
    }

    private var outgoingSections: [PrintableMonthTileSection] {
        detail.sections.filter { $0.id == "group-outgoings" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            summaryRow
            if !detail.accountBalances.isEmpty {
                accountSection
            }
            tileContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("BudgetMate · \(detail.title)")
                .font(PrintTypography.documentTitle)
            if detail.isLocked {
                Image(systemName: "lock.fill")
                    .font(PrintTypography.icon)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(Date.now, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                .font(PrintTypography.documentDate)
                .foregroundStyle(.secondary)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 6) {
            summaryCell("Opening", detail.openingMinorUnits)
            summaryCell("Income", detail.incomeMinorUnits, tint: .green)
            summaryCell("Expenses", detail.expenseMinorUnits, tint: .red)
            summaryCell("Savings", detail.savingMinorUnits)
        }
    }

    private func summaryCell(_ title: String, _ minorUnits: Int, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(PrintTypography.label)
                .foregroundStyle(.secondary)
            Text(MoneyFormatter.format(minorUnits: minorUnits, currency: currency))
                .font(PrintTypography.amountSemibold)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(Color(white: 0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(white: 0.88), lineWidth: 0.5)
        )
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("By account")
                .font(PrintTypography.sectionHeader)
                .foregroundStyle(.secondary)

            ForEach(detail.accountBalances) { account in
                HStack(spacing: 4) {
                    Text(account.name)
                        .font(PrintTypography.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(MoneyFormatter.format(minorUnits: account.openingMinorUnits, currency: currency))
                        .font(PrintTypography.amount)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }

    @ViewBuilder
    private var tileContent: some View {
        if outgoingSections.isEmpty {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                ForEach(detail.sections) { section in
                    tileSection(section)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    ForEach(incomeSections) { section in
                        tileSection(section)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: sectionSpacing) {
                    ForEach(outgoingSections) { section in
                        tileSection(section, allowsTwoColumns: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func tileSection(_ section: PrintableMonthTileSection, allowsTwoColumns: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(section.title)
                    .font(PrintTypography.bodySemibold)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(MoneyFormatter.format(minorUnits: section.totalMinorUnits, currency: currency))
                    .font(PrintTypography.amountSemibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if allowsTwoColumns && section.rows.count >= twoColumnRowThreshold {
                let split = splitRows(section.rows)
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        ForEach(split.left) { row in
                            compactTileRow(row)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: rowSpacing) {
                        ForEach(split.right) { row in
                            compactTileRow(row)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(section.rows) { row in
                        compactTileRow(row)
                    }
                }
            }
        }
    }

    private func compactTileRow(_ row: PrintableMonthTileRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name)
                    .font(PrintTypography.bodyMedium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !row.metadata.isEmpty {
                    Text(row.metadata)
                        .font(PrintTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
            Spacer(minLength: 2)
            Text(MoneyFormatter.format(minorUnits: row.amountMinorUnits, currency: currency))
                .font(PrintTypography.amount)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func splitRows(_ rows: [PrintableMonthTileRow]) -> (left: [PrintableMonthTileRow], right: [PrintableMonthTileRow]) {
        let midpoint = (rows.count + 1) / 2
        return (Array(rows.prefix(midpoint)), Array(rows.suffix(from: midpoint)))
    }
}
