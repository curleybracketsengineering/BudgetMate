import Foundation

enum TransactionAnalysisService {
    private static let calendar = Calendar.current

    static func analyze(
        rows: [ImportPreviewRow],
        payeeNotes: [String: PayeeNote] = [:],
        amountBasis: AmountBasis = .median
    ) -> (suggestions: [BudgetSuggestion], typicalMonth: TypicalMonthSummary) {
        let eligible = rows.filter { $0.budgetType != .transfer }
        let analysisMonthCount = calendarMonthsSpanned(by: eligible)
        let byMerchant = Dictionary(grouping: eligible) { row in
            let merchant = PayeeNormalization.merchantKey(row.transaction.payee)
            let detail = PayeeNormalization.normalize(row.transaction.payee)
            return "\(merchant)|\(detail)"
        }

        var suggestions: [BudgetSuggestion] = []
        var linkedIDs = Set<UUID>()

        for (_, merchantRows) in byMerchant {
            let clusters = PayeeNormalization.clusterByAmount(merchantRows, tolerancePercent: 0.10)
            for cluster in clusters {
                let minimumCount = minimumOccurrences(for: cluster)
                guard cluster.count >= minimumCount else { continue }
                guard let suggestion = detectSuggestion(
                    from: cluster,
                    payeeNotes: payeeNotes,
                    analysisMonthCount: analysisMonthCount,
                    amountBasis: amountBasis
                ) else { continue }
                suggestions.append(suggestion)
                linkedIDs.formUnion(suggestion.linkedTransactionIDs)
            }
        }

        suggestions.sort { lhs, rhs in
            if lhs.budgetType != rhs.budgetType {
                return lhs.budgetType == .income
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let typicalMonth = buildTypicalMonth(
            suggestions: suggestions.filter { !$0.isIgnored },
            remainingRows: eligible.filter { !linkedIDs.contains($0.transaction.id) },
            monthCount: analysisMonthCount
        )

        return (suggestions, typicalMonth)
    }

    /// Builds a recurring suggestion from user-selected transactions (e.g. missed by auto-grouping).
    static func makeManualSuggestion(
        from rows: [ImportPreviewRow],
        payeeNotes: [String: PayeeNote],
        amountBasis: AmountBasis,
        cycle: BudgetCycleType = .monthly
    ) -> BudgetSuggestion? {
        guard !rows.isEmpty else { return nil }

        let sorted = rows.sorted { $0.transaction.date < $1.transaction.date }
        guard let budgetType = sorted.first?.budgetType else { return nil }
        guard budgetType == .income || budgetType == .expense || budgetType == .saving else { return nil }
        guard sorted.allSatisfy({ $0.budgetType == budgetType }) else { return nil }

        let dates = sorted.map(\.transaction.date)
        let amounts = sorted.map(\.transaction.amountMinorUnits)
        guard let firstDate = dates.first else { return nil }

        let payeeSample = sorted.first!.transaction.payee
        let representative = sorted[sorted.count / 2]
        let analysisMonthCount = calendarMonthsSpanned(by: sorted)
        let perOccurrence = perOccurrenceAmount(amounts: amounts, basis: amountBasis)
        let totalMinorUnits = amounts.reduce(0, +)
        let monthlyEquivalent = empiricalMonthlyEquivalent(
            totalMinorUnits: totalMinorUnits,
            analysisMonthCount: analysisMonthCount
        )

        let explanation = manualSuggestionExplanation(
            budgetType: budgetType,
            cycle: cycle,
            paymentCount: sorted.count
        )

        var suggestion = BudgetSuggestion(
            name: PayeeNormalization.displayName(from: payeeSample),
            budgetType: budgetType,
            category: representative.category,
            cycle: cycle,
            amountMinorUnits: perOccurrence,
            monthlyEquivalentMinorUnits: monthlyEquivalent,
            startDate: firstDate,
            lastPaymentDate: dates.last ?? firstDate,
            confidence: .estimated,
            explanation: explanation,
            paymentMethod: PaymentMethodLabel.mostCommon(in: sorted),
            amountMinMinorUnits: amounts.min() ?? perOccurrence,
            amountMaxMinorUnits: amounts.max() ?? perOccurrence,
            transactionCount: sorted.count,
            linkedTransactionIDs: Set(sorted.map(\.transaction.id)),
            isManual: true,
            payeeMatchKey: PayeeNormalization.matchKey(payeeSample),
            bankPayeeSample: payeeSample
        )
        PayeeNoteService.apply(to: &suggestion, payeeSample: payeeSample, notes: payeeNotes)
        return suggestion
    }

    private static func manualSuggestionExplanation(
        budgetType: BudgetType,
        cycle: BudgetCycleType,
        paymentCount: Int
    ) -> String {
        let recurringLabel: String = {
            switch budgetType {
            case .income: "income"
            case .expense: "bill"
            case .saving: "saving"
            default: "payment"
            }
        }()

        switch cycle {
        case .monthly:
            if paymentCount == 1 {
                return "Manually marked as monthly \(recurringLabel) (only one payment in this import; confirm in Budget Rules)."
            }
            return "Manually grouped as monthly \(recurringLabel) — \(paymentCount) payments."
        default:
            return "Manually grouped recurring \(recurringLabel) — \(paymentCount) payment(s)."
        }
    }

    static func typicalMonth(
        suggestions: [BudgetSuggestion],
        previewRows: [ImportPreviewRow]
    ) -> TypicalMonthSummary {
        let eligible = previewRows.filter { $0.budgetType != .transfer }
        let linkedIDs = Set(suggestions.flatMap(\.linkedTransactionIDs))
        let remaining = eligible.filter { !linkedIDs.contains($0.transaction.id) }
        let monthCount = calendarMonthsSpanned(by: eligible)
        return buildTypicalMonth(
            suggestions: suggestions.filter { !$0.isIgnored },
            remainingRows: remaining,
            monthCount: monthCount
        )
    }

    static func inferredCycle(for row: ImportPreviewRow) -> (BudgetCycleType, [Int], String) {
        let payee = row.transaction.payee.uppercased()
        let isKnownIncome = row.budgetType == .income
            && TransactionCategorizationService.isKnownRegularIncomePayee(row.transaction.payee)
        return detectCycle(
            dates: [row.transaction.date],
            payee: payee,
            budgetType: row.budgetType,
            isKnownRegularIncome: isKnownIncome
        )
    }

    // MARK: - Detection

    private static func minimumOccurrences(for cluster: [ImportPreviewRow]) -> Int {
        guard let sample = cluster.first else { return 2 }
        if sample.budgetType == .income,
           TransactionCategorizationService.isKnownRegularIncomePayee(sample.transaction.payee) {
            return 1
        }
        return 2
    }

    private static func detectSuggestion(
        from rows: [ImportPreviewRow],
        payeeNotes: [String: PayeeNote],
        analysisMonthCount: Int,
        amountBasis: AmountBasis
    ) -> BudgetSuggestion? {
        let sorted = rows.sorted { $0.transaction.date < $1.transaction.date }
        let dates = sorted.map(\.transaction.date)
        let amounts = sorted.map(\.transaction.amountMinorUnits)
        guard let firstDate = dates.first else { return nil }

        let representative = sorted[sorted.count / 2]
        let payeeSample = sorted.first!.transaction.payee
        let name = PayeeNormalization.displayName(from: payeeSample)
        let combined = payeeSample.uppercased()

        let medianAmount = median(amounts)
        let minAmount = amounts.min() ?? medianAmount
        let maxAmount = amounts.max() ?? medianAmount
        let amountSpread = amounts.map { abs($0 - medianAmount) }
        let maxSpread = amountSpread.max() ?? 0
        if sorted.count > 1,
           maxSpread > max(500, Int(Double(medianAmount) * 0.10)) { return nil }

        let paymentMethod = PaymentMethodLabel.mostCommon(in: sorted)
        let isKnownIncome = representative.budgetType == .income
            && TransactionCategorizationService.isKnownRegularIncomePayee(payeeSample)

        let (cycle, activeMonths, explanation) = detectCycle(
            dates: dates,
            payee: combined,
            budgetType: representative.budgetType,
            isKnownRegularIncome: isKnownIncome
        )

        guard cycle != .oneOff else { return nil }

        let perOccurrence = perOccurrenceAmount(amounts: amounts, basis: amountBasis)
        let totalMinorUnits = amounts.reduce(0, +)
        let monthlyEquivalent = empiricalMonthlyEquivalent(
            totalMinorUnits: totalMinorUnits,
            analysisMonthCount: analysisMonthCount
        )

        let confidence: ConfidenceLevel = {
            if isKnownIncome && sorted.count == 1 { return .estimated }
            if sorted.count >= 10 { return .known }
            if sorted.count >= 5 { return .estimated }
            return .guess
        }()

        var suggestion = BudgetSuggestion(
            name: name,
            budgetType: representative.budgetType,
            category: representative.category,
            cycle: cycle,
            amountMinorUnits: perOccurrence,
            monthlyEquivalentMinorUnits: monthlyEquivalent,
            activeMonths: activeMonths,
            startDate: firstDate,
            lastPaymentDate: dates.last ?? firstDate,
            confidence: confidence,
            explanation: explanation,
            paymentMethod: paymentMethod,
            amountMinMinorUnits: minAmount,
            amountMaxMinorUnits: maxAmount,
            transactionCount: sorted.count,
            linkedTransactionIDs: Set(sorted.map(\.transaction.id)),
            payeeMatchKey: PayeeNormalization.matchKey(payeeSample),
            bankPayeeSample: payeeSample
        )
        PayeeNoteService.apply(to: &suggestion, payeeSample: payeeSample, notes: payeeNotes)
        return suggestion
    }

    private static func detectCycle(
        dates: [Date],
        payee: String,
        budgetType: BudgetType,
        isKnownRegularIncome: Bool = false
    ) -> (BudgetCycleType, [Int], String) {
        let sorted = dates.sorted()
        let intervals = zip(sorted.dropFirst(), sorted).compactMap { later, earlier -> Int? in
            calendar.dateComponents([.day], from: earlier, to: later).day
        }
        let spanMonths = max(1, calendarMonthsSpanned(dates: sorted))
        let annualisedCount = Double(dates.count) / Double(spanMonths) * 12.0
        let monthsWithPayments = Set(sorted.map { calendar.component(.month, from: $0) })

        if budgetType == .income && isKnownRegularIncome && sorted.count == 1 {
            if hintsFourWeekly(payee: payee) || payee.contains("SEB PENSION") {
                return (.everyFourWeeks, [], "Regular pension income — every 4 weeks (only one payment in this import; confirm in Budget Rules).")
            }
            if payee.contains("ORACLE") || payee.contains("IVALUA") || payee.contains("BGC") {
                return (.monthly, [], "Regular income — monthly (only one payment in this import; confirm in Budget Rules).")
            }
            return (.everyFourWeeks, [], "Regular pension income (only one payment in this import; confirm cycle in Budget Rules).")
        }

        if hintsTenMonthly(payee: payee) || isTenMonthlyPattern(
            dates: sorted,
            monthsWithPayments: monthsWithPayments,
            spanMonths: spanMonths
        ) {
            let active = resolveTenMonthlyMonths(dates: sorted, monthsWithPayments: monthsWithPayments)
            if active.count == 10 {
                let monthNames = active.map { calendar.shortMonthSymbols[$0 - 1] }.joined(separator: ", ")
                return (.tenMonthly, active, "Paid in 10 months per year (\(monthNames)). Skips 2 months.")
            }
        }

        if isCalendarMonthlyPattern(dates: sorted),
           dates.count >= max(2, spanMonths - 1) {
            return (.monthly, [], "Monthly — \(dates.count) payments across \(spanMonths) months.")
        }

        if let medianInterval = medianOptional(intervals) {
            if medianInterval >= 25 && medianInterval <= 32
                && !isCalendarMonthlyPattern(dates: sorted)
                && (annualisedCount >= 12.5 || dates.count >= spanMonths + 1) {
                return (.everyFourWeeks, [], "Every 4 weeks — \(dates.count) payments in \(spanMonths) months (~\(Int(annualisedCount.rounded())) per year).")
            }

            if medianInterval >= 27 && medianInterval <= 35 && dates.count >= max(2, spanMonths - 1) {
                return (.monthly, [], "Monthly — \(dates.count) payments across \(spanMonths) months.")
            }

            if medianInterval >= 85 && medianInterval <= 98 {
                return (.quarterly, [], "Quarterly — roughly every 3 months.")
            }

            if medianInterval >= 175 && medianInterval <= 190 {
                return (.twiceYearly, [], "Twice yearly — roughly every 6 months.")
            }

            if medianInterval >= 350 && medianInterval <= 380 {
                return (.yearly, [], "Yearly payment.")
            }
        }

        if dates.count >= spanMonths - 1 && monthsWithPayments.count >= spanMonths - 1 {
            return (.monthly, [], "Monthly — appears most months in the data.")
        }

        if budgetType == .income && dates.count >= 3
            && !isCalendarMonthlyPattern(dates: sorted)
            && (hintsFourWeekly(payee: payee) || annualisedCount >= 12) {
            return (.everyFourWeeks, [], "Regular income — likely every 4 weeks (\(dates.count) payments).")
        }

        if dates.count >= 3 {
            return (.monthly, [], "Recurring — \(dates.count) similar payments detected.")
        }

        return (.oneOff, [], "One-off")
    }

    private static func hintsTenMonthly(payee: String) -> Bool {
        payee.contains("COUNCIL")
            || payee.contains("WATER")
            || payee.contains("ESSEX")
            || payee.contains("SUFFOLK")
            || payee.contains("RATES")
    }

    private static func hintsFourWeekly(payee: String) -> Bool {
        payee.contains("FORSAKRINGSKASSA")
            || payee.contains("SEB PENSION")
            || payee.contains("DWP")
            || payee.contains("PENSI")
    }

    /// One payment per calendar month on a consistent day (±3 days for weekends/holidays).
    private static func isCalendarMonthlyPattern(dates: [Date]) -> Bool {
        guard dates.count >= 2 else { return false }
        let sorted = dates.sorted()

        var seenYearMonths = Set<String>()
        for date in sorted {
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let key = "\(year)-\(month)"
            if seenYearMonths.contains(key) { return false }
            seenYearMonths.insert(key)
        }

        let days = sorted.map { calendar.component(.day, from: $0) }
        let anchor = median(days)
        return days.allSatisfy { abs($0 - anchor) <= 3 }
    }

    private static func isTenMonthlyPattern(
        dates: [Date],
        monthsWithPayments: Set<Int>,
        spanMonths: Int
    ) -> Bool {
        guard spanMonths >= 10 else { return false }
        guard dates.count >= 8 && dates.count <= 11 else { return false }
        return monthsWithPayments.count == 10
            || (monthsWithPayments.count >= 9 && monthsWithPayments.count <= 11 && dates.count <= 11)
    }

    private static func resolveTenMonthlyMonths(dates: [Date], monthsWithPayments: Set<Int>) -> [Int] {
        if monthsWithPayments.count == 10 {
            return monthsWithPayments.sorted()
        }

        var monthFrequency: [Int: Int] = [:]
        for date in dates {
            let month = calendar.component(.month, from: date)
            monthFrequency[month, default: 0] += 1
        }

        let sortedMonths = monthFrequency.sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }

        let topTen = sortedMonths.prefix(10).map(\.key).sorted()
        return topTen.count == 10 ? topTen : []
    }

    // MARK: - Typical month

    private static func buildTypicalMonth(
        suggestions: [BudgetSuggestion],
        remainingRows: [ImportPreviewRow],
        monthCount: Int
    ) -> TypicalMonthSummary {
        var summary = TypicalMonthSummary(
            suggestionCount: suggestions.count,
            analysisMonthCount: monthCount
        )

        for suggestion in suggestions where !suggestion.isIgnored {
            switch suggestion.budgetType {
            case .income: summary.incomeMinorUnits += suggestion.monthlyEquivalentMinorUnits
            case .expense: summary.expenseMinorUnits += suggestion.monthlyEquivalentMinorUnits
            case .saving: summary.savingMinorUnits += suggestion.monthlyEquivalentMinorUnits
            case .transfer: summary.transferMinorUnits += suggestion.monthlyEquivalentMinorUnits
            case .adjustment: break
            }
        }

        let flexibleRows = remainingRows.filter { $0.budgetType == .expense }
        if !flexibleRows.isEmpty && monthCount > 0 {
            let total = flexibleRows.reduce(0) { $0 + $1.transaction.amountMinorUnits }
            summary.flexibleSpendingMinorUnits = total / monthCount
            summary.expenseMinorUnits += summary.flexibleSpendingMinorUnits
        }

        return summary
    }

    static func empiricalMonthlyEquivalent(totalMinorUnits: Int, analysisMonthCount: Int) -> Int {
        guard analysisMonthCount > 0 else { return totalMinorUnits }
        return totalMinorUnits / analysisMonthCount
    }

    static func monthlyEquivalentAmount(
        perOccurrence: Int,
        cycle: BudgetCycleType,
        activeMonthCount: Int
    ) -> Int {
        switch cycle {
        case .monthly, .weekly:
            return perOccurrence
        case .everyFourWeeks:
            return Int((Double(perOccurrence) * 13.0 / 12.0).rounded())
        case .tenMonthly:
            let months = activeMonthCount > 0 ? activeMonthCount : 10
            return Int((Double(perOccurrence) * Double(months) / 12.0).rounded())
        case .custom:
            guard activeMonthCount > 0 else { return 0 }
            return Int((Double(perOccurrence) * Double(activeMonthCount) / 12.0).rounded())
        case .quarterly:
            return perOccurrence / 3
        case .twiceYearly:
            return perOccurrence / 6
        case .yearly:
            return perOccurrence / 12
        case .oneOff:
            return perOccurrence
        }
    }

    // MARK: - Helpers

    private static func calendarMonthsSpanned(by rows: [ImportPreviewRow]) -> Int {
        calendarMonthsSpanned(dates: rows.map(\.transaction.date))
    }

    private static func calendarMonthsSpanned(dates: [Date]) -> Int {
        guard let first = dates.min(), let last = dates.max() else { return 1 }
        let components = calendar.dateComponents([.month], from: first, to: last)
        return max(1, (components.month ?? 0) + 1)
    }

    private static func perOccurrenceAmount(amounts: [Int], basis: AmountBasis) -> Int {
        switch basis {
        case .median:
            return median(amounts)
        case .latest:
            return amounts.last ?? 0
        }
    }

    private static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func medianOptional(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return median(values)
    }
}
