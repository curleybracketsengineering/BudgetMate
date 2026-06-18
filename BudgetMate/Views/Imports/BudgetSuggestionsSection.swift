import SwiftUI

struct BudgetSuggestionsSection: View {
    @Binding var suggestions: [BudgetSuggestion]
    @Binding var flowFocus: ImportFlowFocus
    @Binding var amountBasis: AmountBasis
    @Binding var paymentMethodFilter: ImportPaymentMethodFilter?
    let typicalMonth: TypicalMonthSummary
    let availablePaymentMethodFilters: [ImportPaymentMethodFilter]
    let previewRowsForPaymentFilter: [ImportPreviewRow]
    let currency: AppCurrency
    let totalIncomingCount: Int
    let totalOutgoingCount: Int
    let previewRows: [ImportPreviewRow]
    let onCreateRules: () -> Void
    let onPayeeNoteSaved: () -> Void
    let offerUndo: (String, @escaping () -> Void) -> Void

    @State private var inspectedSuggestion: InspectedSuggestion?
    @State private var editingPayeeNote: PayeeNoteEditContext?
    @State private var showingCreateRulesConfirmation = false

    private var acceptedCount: Int {
        suggestions.filter(\.isAccepted).count
    }

    private var incomingSuggestions: [BudgetSuggestion] {
        suggestions.filter {
            $0.budgetType == .income && !$0.isIgnored && matchesPaymentMethodFilter($0)
        }
    }

    private var outgoingSuggestions: [BudgetSuggestion] {
        suggestions.filter {
            ($0.budgetType == .expense || $0.budgetType == .saving)
                && !$0.isIgnored
                && matchesPaymentMethodFilter($0)
        }
    }

    private var displayedTypicalMonth: TypicalMonthSummary {
        guard let paymentMethodFilter else { return typicalMonth }
        let scopedSuggestions = suggestions.filter {
            !$0.isIgnored
                && flowFocus.includes(budgetType: $0.budgetType)
                && paymentMethodFilter.matches(paymentMethod: $0.paymentMethod)
        }
        let scopedRows = previewRows.filter {
            flowFocus.includes(budgetType: $0.budgetType)
                && paymentMethodFilter.matches(subcategory: $0.transaction.subcategory)
        }
        return TransactionAnalysisService.typicalMonth(
            suggestions: scopedSuggestions,
            previewRows: scopedRows
        )
    }

    private func matchesPaymentMethodFilter(_ suggestion: BudgetSuggestion) -> Bool {
        guard let paymentMethodFilter else { return true }
        return paymentMethodFilter.matches(paymentMethod: suggestion.paymentMethod)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            typicalMonthSection

            if suggestions.filter({ !$0.isIgnored }).isEmpty {
                Text("No recurring patterns detected yet. Need at least 2 similar payments for the same payee (or a known pension/income source).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if acceptedCount > 0 {
                    createBudgetRulesButton
                }

                if flowFocus == .incoming {
                    suggestionPanel(
                        title: "Incoming — regular income",
                        subtitle: recurringSubtitle(
                            focus: .incoming,
                            suggestionCount: incomingSuggestions.count,
                            transactionCount: totalIncomingCount
                        ),
                        tint: .green,
                        suggestionIDs: incomingSuggestions.map(\.id),
                        emptyMessage: totalIncomingCount == 0
                            ? "No income transactions in this import."
                            : "No recurring income patterns detected — see all income transactions in the preview list below."
                    )
                }

                if flowFocus == .outgoing {
                    suggestionPanel(
                        title: "Outgoing — bills & commitments",
                        subtitle: recurringSubtitle(
                            focus: .outgoing,
                            suggestionCount: outgoingSuggestions.count,
                            transactionCount: totalOutgoingCount
                        ),
                        tint: .red,
                        suggestionIDs: outgoingSuggestions.map(\.id),
                        emptyMessage: totalOutgoingCount == 0
                            ? "No outgoing transactions in this import."
                            : "No recurring outgoing patterns detected — see all outgoing transactions in the preview list below."
                    )
                }
            }
        }
        .sheet(item: $inspectedSuggestion) { selection in
            SuggestionTransactionsSheet(
                suggestionID: selection.id,
                suggestions: $suggestions,
                transactions: linkedTransactions(forID: selection.id),
                currency: currency,
                onPayeeNoteSaved: onPayeeNoteSaved
            )
        }
        .sheet(item: $editingPayeeNote) { context in
            PayeeNoteEditSheet(
                matchKey: context.matchKey,
                samplePayee: context.samplePayee,
                autoGeneratedName: context.autoGeneratedName,
                onSaved: onPayeeNoteSaved
            )
        }
        .sheet(isPresented: $showingCreateRulesConfirmation) {
            CreateBudgetRulesConfirmationSheet(
                suggestions: acceptedSuggestions,
                currency: currency,
                onConfirm: onCreateRules
            )
        }
    }

    private var acceptedSuggestions: [BudgetSuggestion] {
        suggestions.filter(\.isAccepted)
    }

    private func linkedTransactions(forID suggestionID: UUID) -> [ImportPreviewRow] {
        guard let suggestion = suggestions.first(where: { $0.id == suggestionID }) else { return [] }
        return linkedTransactions(for: suggestion)
    }

    private func linkedTransactions(for suggestion: BudgetSuggestion) -> [ImportPreviewRow] {
        previewRows
            .filter { suggestion.linkedTransactionIDs.contains($0.id) }
            .sorted { $0.transaction.date > $1.transaction.date }
    }

    private func recurringSubtitle(
        focus: ImportFlowFocus,
        suggestionCount: Int,
        transactionCount: Int
    ) -> String {
        let linked = suggestions
            .filter {
                focus.includes(budgetType: $0.budgetType)
                    && !$0.isIgnored
                    && matchesPaymentMethodFilter($0)
            }
            .reduce(0) { $0 + $1.transactionCount }
        let other = max(0, transactionCount - linked)
        if other > 0 {
            return "\(suggestionCount) recurring group(s) from \(linked) transactions · \(other) other \(focus == .incoming ? "income" : "outgoing") item(s) in preview below."
        }
        return "\(suggestionCount) recurring group(s) covering \(linked) \(focus == .incoming ? "income" : "outgoing") transactions."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Suggested budget from history")
                    .font(.title3.weight(.semibold))
                Text("Preview only — nothing is saved until you review and confirm. Similar payments are grouped by payee (within 10% amount variance).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if acceptedCount > 0 {
                Label(
                    "\(acceptedCount) selected for saving — not in Budget Rules yet",
                    systemImage: "info.circle"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Per payment basis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Per payment basis", selection: $amountBasis) {
                    ForEach(AmountBasis.allCases) { basis in
                        Text(basis.displayName).tag(basis)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(amountBasisHelpText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var amountBasisHelpText: String {
        switch amountBasis {
        case .median:
            "Median uses the middle payment across this import — stable when amounts vary slightly."
        case .latest:
            "Latest uses your most recent payment — useful when costs are rising."
        }
    }

    private var createBudgetRulesButton: some View {
        Button {
            showingCreateRulesConfirmation = true
        } label: {
            Label("Create budget rules", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .help("Review your selection before saving rules to Budget Rules")
    }

    private var typicalMonthSectionTitle: String {
        "Typical month (from \(displayedTypicalMonth.analysisMonthCount) months of data)"
    }

    private var paymentMethodFilterSection: some View {
        HStack(spacing: 8) {
            Text("Payment type")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            FilterChip(title: "All", isSelected: paymentMethodFilter == nil) {
                paymentMethodFilter = nil
            }
            ForEach(availablePaymentMethodFilters) { method in
                let count = previewRowsForPaymentFilter.filter {
                    flowFocus.includes(budgetType: $0.budgetType)
                        && method.matches(subcategory: $0.transaction.subcategory)
                }.count
                if count > 0 {
                    FilterChip(
                        title: "\(method.title) (\(count))",
                        isSelected: paymentMethodFilter == method
                    ) {
                        paymentMethodFilter = method
                    }
                }
            }
        }
    }

    private var typicalMonthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(typicalMonthSectionTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if availablePaymentMethodFilters.count > 1 {
                HStack {
                    Spacer(minLength: 0)
                    paymentMethodFilterSection
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 10) {
                SummaryCard(
                    title: "Income / month",
                    amount: MoneyFormatter.format(minorUnits: displayedTypicalMonth.incomeMinorUnits, currency: currency),
                    tint: .green
                )
                SummaryCard(
                    title: "Bills / month",
                    amount: MoneyFormatter.format(minorUnits: displayedTypicalMonth.expenseMinorUnits, currency: currency),
                    tint: .red
                )
                SummaryCard(
                    title: "Savings / month",
                    amount: MoneyFormatter.format(minorUnits: displayedTypicalMonth.savingMinorUnits, currency: currency)
                )
                if displayedTypicalMonth.flexibleSpendingMinorUnits > 0 {
                    SummaryCard(
                        title: "Flexible spend",
                        amount: MoneyFormatter.format(minorUnits: displayedTypicalMonth.flexibleSpendingMinorUnits, currency: currency)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func suggestionPanel(
        title: String,
        subtitle: String,
        tint: Color,
        suggestionIDs: [UUID],
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(suggestionIDs.count) items")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if suggestionIDs.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                SuggestionsListTable(
                    suggestions: $suggestions,
                    currency: currency,
                    amountBasis: amountBasis,
                    includedIDs: Set(suggestionIDs),
                    offerUndo: offerUndo,
                    onInspect: { inspectedSuggestion = InspectedSuggestion(id: $0) },
                    onEditPayeeNote: { suggestion in
                        editingPayeeNote = PayeeNoteEditContext(
                            matchKey: suggestion.payeeMatchKey,
                            samplePayee: suggestion.bankPayeeSample,
                            autoGeneratedName: PayeeNormalization.displayName(from: suggestion.bankPayeeSample)
                        )
                    }
                )
            }
        }
        .padding(12)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.15)))
    }
}

private struct SuggestionsListTable: View {
    @Binding var suggestions: [BudgetSuggestion]
    let currency: AppCurrency
    let amountBasis: AmountBasis
    let includedIDs: Set<UUID>
    let offerUndo: (String, @escaping () -> Void) -> Void
    let onInspect: (UUID) -> Void
    let onEditPayeeNote: (BudgetSuggestion) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            SuggestionRowHeader(amountBasis: amountBasis)
            Divider()
            ForEach($suggestions) { $suggestion in
                if includedIDs.contains(suggestion.id) && !suggestion.isIgnored {
                    BudgetSuggestionRowView(
                        suggestion: $suggestion,
                        suggestions: $suggestions,
                        currency: currency,
                        amountBasis: amountBasis,
                        offerUndo: offerUndo,
                        onInspect: { onInspect(suggestion.id) },
                        onEditPayeeNote: { onEditPayeeNote(suggestion) }
                    )
                    Divider()
                }
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }
}

private struct SuggestionRowHeader: View {
    let amountBasis: AmountBasis

    var body: some View {
        HStack(spacing: 10) {
            Text("Save")
                .frame(width: 28)
            Text("Payee")
                .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            Text("Cycle")
                .frame(width: 100, alignment: .leading)
            Text("Last paid")
                .frame(width: 72, alignment: .leading)
            Text(amountBasis.perPaymentColumnTitle)
                .frame(width: 100, alignment: .trailing)
            Text("Count")
                .frame(width: 40, alignment: .trailing)
            Text("")
                .frame(width: 56)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct BudgetSuggestionRowView: View {
    @Binding var suggestion: BudgetSuggestion
    @Binding var suggestions: [BudgetSuggestion]
    let currency: AppCurrency
    let amountBasis: AmountBasis
    let offerUndo: (String, @escaping () -> Void) -> Void
    let onInspect: () -> Void
    let onEditPayeeNote: () -> Void

    private var perPaymentLabel: String {
        switch amountBasis {
        case .latest:
            return MoneyFormatter.format(minorUnits: suggestion.amountMinorUnits, currency: currency)
        case .median:
            if suggestion.hasAmountVariance {
                return "\(MoneyFormatter.format(minorUnits: suggestion.amountMinMinorUnits, currency: currency)) – \(MoneyFormatter.format(minorUnits: suggestion.amountMaxMinorUnits, currency: currency))"
            }
            return MoneyFormatter.format(minorUnits: suggestion.amountMinorUnits, currency: currency)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                suggestion.isAccepted.toggle()
            } label: {
                Image(systemName: suggestion.isAccepted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(suggestion.isAccepted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 28)
            .help(suggestion.isAccepted ? "Selected to save as a budget rule" : "Select to save as a budget rule")

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(suggestion.name)
                            .font(.body.weight(.medium))
                            .lineLimit(2)
                        Button(action: onEditPayeeNote) {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Edit label & notes")
                    }
                    if !suggestion.bankPayeeSample.isEmpty,
                       suggestion.name.caseInsensitiveCompare(
                        PayeeNormalization.displayName(from: suggestion.bankPayeeSample)
                       ) != .orderedSame {
                        Text(suggestion.bankPayeeSample)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        if !suggestion.category.isEmpty {
                            Text(suggestion.category)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                        Text(suggestion.paymentMethod)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(suggestion.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if !suggestion.userNotes.isEmpty {
                        Text(suggestion.userNotes)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .italic()
                            .lineLimit(2)
                    }
                }
                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

                Text(suggestion.cycle.displayName)
                    .font(.caption)
                    .frame(width: 100, alignment: .leading)
                    .lineLimit(2)

                Text(suggestion.lastPaymentDate.formatted(.dateTime.month(.abbreviated).year()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                    .lineLimit(1)

                Text(perPaymentLabel)
                    .font(.caption.monospacedDigit())
                    .frame(width: 100, alignment: .trailing)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)

                Text("\(suggestion.transactionCount)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onInspect)
            .help("View \(suggestion.transactionCount) transaction(s) in this group")
            .contextMenu {
                Button("View transactions", systemImage: "list.bullet") {
                    onInspect()
                }
                Button("Edit label & notes", systemImage: "pencil") {
                    onEditPayeeNote()
                }
            }

            Button("Ignore") {
                let suggestionID = suggestion.id
                let name = suggestion.name
                let wasAccepted = suggestion.isAccepted
                suggestion.isIgnored = true
                suggestion.isAccepted = false
                offerUndo("Ignored \(name)") {
                    guard let index = suggestions.firstIndex(where: { $0.id == suggestionID }) else { return }
                    suggestions[index].isIgnored = false
                    suggestions[index].isAccepted = wasAccepted
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .frame(width: 56)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(suggestion.isAccepted ? 1 : 0.95)
    }
}

private struct SuggestionTransactionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let suggestionID: UUID
    @Binding var suggestions: [BudgetSuggestion]
    let transactions: [ImportPreviewRow]
    let currency: AppCurrency
    let onPayeeNoteSaved: () -> Void

    @State private var editingPayeeNote: PayeeNoteEditContext?

    private var suggestion: BudgetSuggestion? {
        suggestions.first { $0.id == suggestionID }
    }

    private var totalMinorUnits: Int {
        transactions.reduce(0) { $0 + $1.transaction.amountMinorUnits }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if let suggestion {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(suggestion.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !suggestion.userNotes.isEmpty {
                            Text(suggestion.userNotes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                        Text("\(transactions.count) transaction(s) · \(MoneyFormatter.format(minorUnits: totalMinorUnits, currency: currency)) total")
                            .font(.caption.weight(.medium))
                    }
                    .padding()

                    if transactions.isEmpty {
                        ContentUnavailableView(
                            "No transactions found",
                            systemImage: "tray",
                            description: Text("These transactions may have been excluded from the import preview.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        LazyVStack(spacing: 0) {
                            SuggestionTransactionRowHeader()
                            Divider()
                            ForEach(transactions) { row in
                                SuggestionTransactionRowView(row: row, currency: currency)
                                Divider()
                            }
                        }
                        .background(.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle(suggestion?.name ?? "Transactions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if let suggestion {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit label", systemImage: "pencil") {
                            editingPayeeNote = PayeeNoteEditContext(
                                matchKey: suggestion.payeeMatchKey,
                                samplePayee: suggestion.bankPayeeSample,
                                autoGeneratedName: PayeeNormalization.displayName(from: suggestion.bankPayeeSample)
                            )
                        }
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 320)
        .sheet(item: $editingPayeeNote) { context in
            PayeeNoteEditSheet(
                matchKey: context.matchKey,
                samplePayee: context.samplePayee,
                autoGeneratedName: context.autoGeneratedName,
                onSaved: onPayeeNoteSaved
            )
        }
    }
}

private struct SuggestionTransactionRowHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Date")
                .frame(width: 90, alignment: .leading)
            Text("Payee")
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
            Text("Reference")
                .frame(width: 90, alignment: .leading)
            Text("Amount")
                .frame(width: 90, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct SuggestionTransactionRowView: View {
    let row: ImportPreviewRow
    let currency: AppCurrency

    var body: some View {
        HStack(spacing: 12) {
            Text(row.transaction.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .frame(width: 90, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.transaction.payee)
                    .font(.body)
                    .lineLimit(1)
                if !row.transaction.memo.isEmpty {
                    Text(row.transaction.memo)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

            Text(row.transaction.referenceNumber.isEmpty ? "—" : row.transaction.referenceNumber)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)

            Text(MoneyFormatter.format(minorUnits: row.transaction.amountMinorUnits, currency: currency))
                .font(.body.monospacedDigit())
                .foregroundStyle(row.budgetType == .income ? .green : .primary)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct InspectedSuggestion: Identifiable {
    let id: UUID
}

private struct PayeeNoteEditContext: Identifiable {
    let matchKey: String
    let samplePayee: String
    let autoGeneratedName: String

    var id: String { matchKey }
}
