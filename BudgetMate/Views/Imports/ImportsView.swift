import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(FeatureGateService.self) private var featureGate
    @Environment(ImportSessionStore.self) private var importSession
    @Query private var settingsList: [AppSettings]
    @Query(sort: \PayeeNote.matchKey) private var payeeNotes: [PayeeNote]

    @State private var showingImporter = false
    @State private var typeFilter: BudgetType?
    @State private var paymentMethodFilter: ImportPaymentMethodFilter?
    @State private var transactionSearchText = ""
    @State private var showingExcluded = false
    @State private var editingPayeeNote: PayeeNoteEditContext?
    @State private var pendingUndo: PendingUndo?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var selectedTransactionIDs: Set<UUID> = []

    private var settings: AppSettings? { settingsList.first }
    private var currency: AppCurrency { settings?.currency ?? .GBP }
    private var canImport: Bool {
        featureGate.isAvailable(.csvImport) && !importSession.previewRows.isEmpty
    }

    private var filteredRows: [ImportPreviewRow] {
        var rows = transactionRowsBeforeSearch
        let query = transactionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            rows = rows.filter { rowMatchesPayeeSearch($0, query: query) }
        }
        return rows
    }

    private var transactionRowsBeforeSearch: [ImportPreviewRow] {
        var rows = importSession.previewRows.filter {
            importSession.flowFocus.includes(budgetType: $0.budgetType)
        }
        if let typeFilter {
            rows = rows.filter { $0.budgetType == typeFilter }
        }
        if let paymentMethodFilter {
            rows = rows.filter { paymentMethodFilter.matches(subcategory: $0.transaction.subcategory) }
        }
        return rows
    }

    private var isTransactionSearchActive: Bool {
        !transactionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var linkedFocusTransactionIDs: Set<UUID> {
        importSession.linkedTransactionIDs(for: importSession.flowFocus)
    }

    private var showsTransactionSelection: Bool {
        importSession.flowFocus == .incoming || importSession.flowFocus == .outgoing
    }

    private var incomingTransactionCount: Int {
        filteredRowCount(matching: .incoming)
    }

    private var outgoingTransactionCount: Int {
        filteredRowCount(matching: .outgoing)
    }

    private func filteredRowCount(matching focus: ImportFlowFocus) -> Int {
        var rows = importSession.rows(matching: focus)
        if let paymentMethodFilter {
            rows = rows.filter { paymentMethodFilter.matches(subcategory: $0.transaction.subcategory) }
        }
        return rows.count
    }

    private var availablePaymentMethodFilters: [ImportPaymentMethodFilter] {
        let present = Set(
            importSession.previewRows
                .filter { importSession.flowFocus.includes(budgetType: $0.budgetType) }
                .map { ImportPaymentMethodFilter.from(subcategory: $0.transaction.subcategory) }
        )
        return ImportPaymentMethodFilter.displayOrder.filter { present.contains($0) }
    }

    private var totals: MonthTotals {
        BankImportService.summaryTotals(for: importSession.previewRows)
    }

    private var payeeNoteIndex: [String: PayeeNote] {
        PayeeNoteService.index(payeeNotes)
    }

    private var acceptedRulesCount: Int {
        importSession.budgetSuggestions.filter(\.isAccepted).count
    }

    private var hasSelectableSuggestions: Bool {
        importSession.budgetSuggestions.contains { !$0.isIgnored }
    }

    private var rulesWereSaved: Bool {
        importSession.importMessage?.localizedCaseInsensitiveContains("budget rule") == true
    }

    private var workflowSteps: [ImportWorkflowStep] {
        let step1: ImportWorkflowStep.State = importSession.hasLoadedFile ? .complete : .current
        let step2: ImportWorkflowStep.State = {
            guard importSession.hasLoadedFile else { return .upcoming }
            if rulesWereSaved || !hasSelectableSuggestions { return .complete }
            return .current
        }()
        let step3: ImportWorkflowStep.State = {
            guard importSession.hasLoadedFile else { return .upcoming }
            if importSession.previewRows.isEmpty && rulesWereSaved { return .complete }
            return canImport ? .current : .upcoming
        }()
        let step2Subtitle: String = {
            if rulesWereSaved { return "Rules saved to Budget Rules" }
            if acceptedRulesCount > 0 { return "\(acceptedRulesCount) selected — press Create budget rules" }
            if !hasSelectableSuggestions { return "No recurring patterns found" }
            return "Tick incoming & outgoing items below"
        }()
        let step3Subtitle: String = {
            if step3 == .complete { return "Tiles added to monthly plan" }
            if canImport { return "Import one-offs below or press Import \(importSession.previewRows.count) tiles" }
            return "Add one-off tiles to monthly plan"
        }()
        return [
            ImportWorkflowStep(number: 1, icon: "doc.badge.plus", title: "Import document", subtitle: "Choose bank export", state: step1),
            ImportWorkflowStep(number: 2, icon: "list.bullet.rectangle.fill", title: "Pick budget rules", subtitle: step2Subtitle, state: step2),
            ImportWorkflowStep(number: 3, icon: "square.grid.2x2.fill", title: "Import tiles", subtitle: step3Subtitle, state: step3)
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Imports")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .data, .qbo],
            allowsMultipleSelection: false
        ) { handleImport(result: $0) }
        .onAppear(perform: syncPayeeNotes)
        .onChange(of: payeeNotes.count) { syncPayeeNotes() }
        .sheet(item: $editingPayeeNote) { context in
            PayeeNoteEditSheet(
                matchKey: context.matchKey,
                samplePayee: context.samplePayee,
                autoGeneratedName: context.autoGeneratedName,
                onSaved: syncPayeeNotes
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bank import")
                        .font(.title2.weight(.semibold))
                    Text("Import CSV or QBO (OFX) bank exports and map transactions to budget tiles.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let importedFileName = importSession.importedFileName {
                        HStack(spacing: 6) {
                            Text(importedFileName)
                            if let importedFormat = importSession.importedFormat {
                                Text("·")
                                Text(importedFormat.displayName)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

            if !featureGate.isAvailable(.csvImport) {
                Label("Pro feature", systemImage: "star.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            if importSession.hasLoadedFile {
                Button {
                    importSession.clear()
                    typeFilter = nil
                    paymentMethodFilter = nil
                    transactionSearchText = ""
                    selectedTransactionIDs = []
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
            }

            Button {
                showingImporter = true
            } label: {
                Label("Choose file…", systemImage: "doc.badge.plus")
            }

            Button {
                performImport()
            } label: {
                Label("Import \(importSession.previewRows.count) tiles", systemImage: "square.and.arrow.down")
            }
            .disabled(!canImport)
            }

            ImportWorkflowStepsView(steps: workflowSteps)
                .frame(maxWidth: .infinity)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if let parseError = importSession.parseError, !importSession.hasLoadedFile {
            ContentUnavailableView(
                "Could not read file",
                systemImage: "exclamationmark.triangle",
                description: Text(parseError)
            )
        } else if importSession.previewRows.isEmpty && !importSession.hasLoadedFile {
            VStack(spacing: 20) {
                ContentUnavailableView(
                    "No file loaded",
                    systemImage: "tray.and.arrow.down",
                    description: Text("Choose a bank CSV or QBO (OFX) export to preview transactions before importing.")
                )
                Button {
                    showingImporter = true
                } label: {
                    Label("Choose file…", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let importMessage = importSession.importMessage {
                        Text(importMessage)
                            .font(.subheadline)
                            .foregroundStyle(.green)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    summarySection
                    flowFocusPicker
                    BudgetSuggestionsSection(
                        suggestions: Bindable(importSession).budgetSuggestions,
                        flowFocus: Bindable(importSession).flowFocus,
                        amountBasis: Bindable(importSession).amountBasis,
                        paymentMethodFilter: $paymentMethodFilter,
                        typicalMonth: importSession.typicalMonth,
                        availablePaymentMethodFilters: availablePaymentMethodFilters,
                        previewRowsForPaymentFilter: importSession.previewRows,
                        currency: currency,
                        totalIncomingCount: incomingTransactionCount,
                        totalOutgoingCount: outgoingTransactionCount,
                        previewRows: importSession.previewRows + importSession.excludedRows,
                        onCreateRules: createBudgetRules,
                        onPayeeNoteSaved: syncPayeeNotes,
                        offerUndo: presentUndo
                    )
                    if importSession.flowFocus == .outgoing {
                        filterSection
                    }
                    transactionsSection
                    excludedSection
                }
                .padding()
            }
            .overlay(alignment: .bottom) {
                if let pendingUndo {
                    UndoBanner(message: pendingUndo.message, onUndo: performUndo)
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: pendingUndo?.message)
            .onChange(of: importSession.amountBasis) {
                importSession.refreshAnalysis()
            }
        }
    }

    private var flowFocusPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Show", selection: Bindable(importSession).flowFocus) {
                ForEach(ImportFlowFocus.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: importSession.flowFocus) {
                typeFilter = nil
                transactionSearchText = ""
                selectedTransactionIDs = []
                if let paymentMethodFilter,
                   !availablePaymentMethodFilters.contains(paymentMethodFilter) {
                    self.paymentMethodFilter = nil
                }
            }

            Text(flowFocusHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var flowFocusHelpText: String {
        let filterNote = paymentMethodFilter.map { " · \($0.title)" } ?? ""
        switch importSession.flowFocus {
        case .incoming:
            return "Showing \(incomingTransactionCount) income transaction(s)\(filterNote) — recurring suggestions above, all matching income items in the preview below."
        case .outgoing:
            return "Showing \(outgoingTransactionCount) outgoing transaction(s)\(filterNote) — select items below to group recurring bills & savings above, or import one-offs."
        }
    }

    private var summarySection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
            SummaryCard(title: "Transactions", amount: "\(importSession.previewRows.count)", tint: .primary)
            SummaryCard(title: "Income", amount: MoneyFormatter.format(minorUnits: totals.income, currency: currency), tint: .green)
            SummaryCard(title: "Expenses", amount: MoneyFormatter.format(minorUnits: totals.expense, currency: currency), tint: .red)
            SummaryCard(title: "Savings", amount: MoneyFormatter.format(minorUnits: totals.saving, currency: currency))
            SummaryCard(title: "Transfers", amount: MoneyFormatter.format(minorUnits: totals.transfer, currency: currency))
        }
    }

    private var filterSection: some View {
        HStack(spacing: 8) {
            Text("Filter")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            FilterChip(title: "All", isSelected: typeFilter == nil) { typeFilter = nil }
            ForEach(outgoingFilterTypes) { type in
                let count = importSession.previewRows.filter { $0.budgetType == type }.count
                if count > 0 {
                    FilterChip(title: "\(type.displayName) (\(count))", isSelected: typeFilter == type) {
                        typeFilter = type
                    }
                }
            }
        }
    }

    private var outgoingFilterTypes: [BudgetType] {
        [.expense, .saving]
    }

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(previewSectionTitle)
                    .font(.title3.weight(.semibold))
                Spacer()
                if isTransactionSearchActive {
                    Text("\(filteredRows.count) shown · \(transactionRowsBeforeSearch.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(filteredRows.count) shown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !importSession.excludedRows.isEmpty {
                    Text("· \(importSession.excludedRows.count) excluded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(transactionsHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if showsTransactionSelection && !selectedTransactionIDs.isEmpty {
                transactionSelectionBar
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search payee…", text: $transactionSearchText)
                    .textFieldStyle(.roundedBorder)
                if !transactionSearchText.isEmpty {
                    Button {
                        transactionSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .frame(maxWidth: 320, alignment: .leading)

            LazyVStack(spacing: 0) {
                ImportRowHeader(showsSelection: showsTransactionSelection)
                Divider()
                ForEach(filteredRows) { row in
                    let isLinked = showsTransactionSelection && linkedFocusTransactionIDs.contains(row.id)
                    let isSelectable = showsTransactionSelection
                        && importSession.flowFocus.includes(budgetType: row.budgetType)
                        && !isLinked
                    ImportTransactionRowView(
                        row: binding(for: row),
                        currency: currency,
                        payeeNoteIndex: payeeNoteIndex,
                        showsSelection: showsTransactionSelection,
                        isSelectable: isSelectable,
                        isSelected: selectedTransactionIDs.contains(row.id),
                        onToggleSelection: {
                            toggleTransactionSelection(row.id)
                        },
                        onImport: { importRowWithUndo(row) },
                        onCreateRecurringRule: { createRecurringRuleWithUndo(row) },
                        onRemove: { excludeRowWithUndo(row) },
                        onEditPayeeNote: {
                            editingPayeeNote = PayeeNoteEditContext(
                                matchKey: PayeeNormalization.matchKey(row.transaction.payee),
                                samplePayee: row.transaction.payee,
                                autoGeneratedName: PayeeNormalization.displayName(from: row.transaction.payee)
                            )
                        }
                    )
                    Divider()
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
        }
    }

    private var previewSectionTitle: String {
        switch importSession.flowFocus {
        case .incoming: "Incoming transactions"
        case .outgoing: "Outgoing transactions"
        }
    }

    private var transactionsHelpText: String {
        switch importSession.flowFocus {
        case .incoming:
            return "Select income items with the round buttons to group missed recurring payments as monthly income above. You can also import one-off tiles, create a single recurring rule, or exclude items."
        case .outgoing:
            return "Select bills, direct debits, or savings items with the round buttons to group missed recurring payments above. You can also import one-off tiles, create a single recurring rule, or exclude items."
        }
    }

    private var selectedRowsBudgetType: BudgetType? {
        let types = Set(
            importSession.previewRows
                .filter { selectedTransactionIDs.contains($0.id) }
                .map(\.budgetType)
        )
        guard types.count == 1, let type = types.first else { return nil }
        return type
    }

    private var groupSelectedButtonTitle: String {
        switch selectedRowsBudgetType {
        case .income: "Group as monthly income"
        case .expense: "Group as monthly bill"
        case .saving: "Group as monthly saving"
        default: "Group as recurring"
        }
    }

    private var transactionSelectionBar: some View {
        HStack(spacing: 12) {
            Text("\(selectedTransactionIDs.count) selected")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Button {
                groupSelectedTransactions()
            } label: {
                Label(groupSelectedButtonTitle, systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(selectedRowsBudgetType == nil)

            if selectedRowsBudgetType == nil && !selectedTransactionIDs.isEmpty {
                Text("Select items of the same type")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Clear selection") {
                selectedTransactionIDs = []
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func toggleTransactionSelection(_ id: UUID) {
        if selectedTransactionIDs.contains(id) {
            selectedTransactionIDs.remove(id)
        } else {
            selectedTransactionIDs.insert(id)
        }
    }

    private func groupSelectedTransactions() {
        let rows = importSession.previewRows.filter { selectedTransactionIDs.contains($0.id) }
        guard !rows.isEmpty else {
            selectedTransactionIDs = []
            return
        }

        guard let suggestion = importSession.addManualSuggestion(from: rows, cycle: .monthly) else {
            importSession.parseError = "Could not group selected transactions — select items of the same type (income, bill, or saving)."
            return
        }

        selectedTransactionIDs = []
        let sectionLabel = recurringSectionLabel(for: suggestion.budgetType)
        importSession.importMessage = "Added \"\(suggestion.name)\" to \(sectionLabel) above."
        let suggestionID = suggestion.id
        presentUndo(message: "Grouped \(suggestion.name) as \(sectionLabel)") {
            importSession.removeSuggestion(id: suggestionID)
        }
    }

    private func recurringSectionLabel(for budgetType: BudgetType) -> String {
        switch budgetType {
        case .income: "recurring income"
        case .expense: "recurring bills"
        case .saving: "recurring savings"
        default: "recurring items"
        }
    }

    @ViewBuilder
    private var excludedSection: some View {
        if !importSession.excludedRows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showingExcluded.toggle()
                } label: {
                    HStack {
                        Text("Excluded from import (\(importSession.excludedRows.count))")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: showingExcluded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)

                if showingExcluded {
                    LazyVStack(spacing: 0) {
                        ForEach(importSession.excludedRows) { row in
                            ExcludedTransactionRowView(
                                row: row,
                                currency: currency,
                                onRestore: { importSession.restoreRow(row) }
                            )
                            Divider()
                        }
                    }
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func syncPayeeNotes() {
        try? PayeeNoteService.deduplicate(in: modelContext)
        importSession.payeeNotes = payeeNoteIndex
        importSession.refreshAnalysis()
    }

    private func rowMatchesPayeeSearch(_ row: ImportPreviewRow, query: String) -> Bool {
        let labels = PayeeNoteService.resolvedPayeeLabels(for: row.transaction.payee, in: payeeNoteIndex)
        let fields = [row.transaction.payee, labels.title, labels.subtitle].compactMap { $0 }
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func presentUndo(message: String, restore: @escaping () -> Void) {
        undoDismissTask?.cancel()
        pendingUndo = PendingUndo(message: message, restore: restore)
        undoDismissTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                pendingUndo = nil
            }
        }
    }

    private func performUndo() {
        undoDismissTask?.cancel()
        pendingUndo?.restore()
        pendingUndo = nil
    }

    private func excludeRowWithUndo(_ row: ImportPreviewRow) {
        selectedTransactionIDs.remove(row.id)
        importSession.excludeRow(row)
        let payee = PayeeNoteService.resolvedPayeeLabels(
            for: row.transaction.payee,
            in: payeeNoteIndex
        ).title
        presentUndo(message: "Excluded \(payee)") {
            importSession.restoreRow(row)
        }
    }

    private func importRowWithUndo(_ row: ImportPreviewRow) {
        guard featureGate.isAvailable(.csvImport) else { return }

        do {
            let result = try BankImportService.importTiles(rows: [row], in: modelContext)
            importSession.removeImportedRow(row)
            let payee = PayeeNoteService.resolvedPayeeLabels(
                for: row.transaction.payee,
                in: payeeNoteIndex
            ).title
            let monthKey = result.monthsAffected.sorted().first ?? row.transaction.date.formatted(.dateTime.month(.abbreviated).year())
            importSession.importMessage = "Imported one-off tile for \(payee) in \(monthKey)."
            let importedTileIDs = result.tileIDs
            presentUndo(message: "Imported \(payee)") {
                do {
                    try BankImportService.deleteTiles(ids: importedTileIDs, in: modelContext)
                    importSession.restoreImportedRow(row)
                } catch {
                    importSession.parseError = error.localizedDescription
                }
            }
        } catch {
            importSession.parseError = error.localizedDescription
        }
    }

    private func createRecurringRuleWithUndo(_ row: ImportPreviewRow) {
        guard featureGate.isAvailable(.csvImport) else { return }

        do {
            let result = try BudgetSuggestionService.createRule(
                from: row,
                payeeNotes: payeeNoteIndex,
                in: modelContext
            )
            importSession.excludeRow(row)
            importSession.importMessage = "Created recurring budget rule \"\(result.name)\" in Budget Rules and generated forecast tiles."
            let ruleID = result.ruleID
            presentUndo(message: "Created recurring rule for \(result.name)") {
                do {
                    try BudgetSuggestionService.deleteRule(id: ruleID, in: modelContext)
                    importSession.restoreRow(row)
                    importSession.refreshAnalysis()
                } catch {
                    importSession.parseError = error.localizedDescription
                }
            }
            importSession.refreshAnalysis()
        } catch {
            importSession.parseError = error.localizedDescription
        }
    }

    private func createBudgetRules() {
        do {
            let count = try BudgetSuggestionService.createRules(from: importSession.budgetSuggestions, in: modelContext)
            BudgetSuggestionService.excludeLinkedTransactions(
                suggestions: importSession.budgetSuggestions,
                from: &importSession.previewRows,
                into: &importSession.excludedRows
            )
            importSession.importMessage = "Saved \(count) budget rule(s) to Budget Rules and generated forecast tiles. Linked transactions moved to excluded."
            importSession.refreshAnalysis()
        } catch {
            importSession.parseError = error.localizedDescription
        }
    }

    private func binding(for row: ImportPreviewRow) -> Binding<ImportPreviewRow> {
        guard let index = importSession.previewRows.firstIndex(where: { $0.id == row.id }) else {
            return .constant(row)
        }
        return Bindable(importSession).previewRows[index]
    }

    private func handleImport(result: Result<[URL], Error>) {
        importSession.parseError = nil
        importSession.importMessage = nil

        switch result {
        case .failure(let error):
            importSession.parseError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            loadFile(at: url)
        }
    }

    private func loadFile(at url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let result = try BankFileParser.parse(data: data, filename: url.lastPathComponent)
            importSession.load(
                transactions: result.transactions,
                filename: url.lastPathComponent,
                format: result.format
            )
            syncPayeeNotes()
            typeFilter = nil
            paymentMethodFilter = nil
            transactionSearchText = ""
            showingExcluded = false
            selectedTransactionIDs = []
        } catch {
            importSession.loadFailed(error.localizedDescription)
        }
    }

    private func performImport() {
        guard canImport else { return }

        do {
            let result = try BankImportService.importTiles(rows: importSession.previewRows, in: modelContext)
            let monthList = result.monthsAffected.sorted().joined(separator: ", ")
            importSession.importMessage = "Imported \(result.tilesCreated) one-off tile(s) across \(result.monthsAffected.count) month(s): \(monthList)."
            importSession.clear(keepMessages: true)
            typeFilter = nil
        } catch {
            importSession.importMessage = nil
            importSession.parseError = error.localizedDescription
        }
    }
}

private struct ImportWorkflowStep: Identifiable {
    enum State {
        case upcoming, current, complete
    }

    let number: Int
    let icon: String
    let title: String
    let subtitle: String
    let state: State

    var id: Int { number }
}

private struct ImportWorkflowStepsView: View {
    private let badgeSize: CGFloat = 44
    private let connectorHeight: CGFloat = 3

    let steps: [ImportWorkflowStep]

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 {
                        stepConnector(from: steps[index - 1].state)
                            .frame(maxWidth: .infinity)
                    }
                    stepBadge(step)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(steps) { step in
                    stepLabels(step)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.35))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.quaternary, lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func stepLabels(_ step: ImportWorkflowStep) -> some View {
        VStack(spacing: 4) {
            Text(step.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(step.state == .upcoming ? .tertiary : .primary)
                .multilineTextAlignment(.center)
            Text(step.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(step.state == .upcoming ? 0.6 : 1)
    }

    @ViewBuilder
    private func stepBadge(_ step: ImportWorkflowStep) -> some View {
        ZStack {
            Circle()
                .fill(stepBackground(step.state))
                .frame(width: badgeSize, height: badgeSize)
                .overlay {
                    if step.state == .current {
                        Circle()
                            .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 4)
                            .frame(width: badgeSize + 8, height: badgeSize + 8)
                    }
                }

            Group {
                switch step.state {
                case .complete:
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                case .current, .upcoming:
                    Image(systemName: step.icon)
                        .font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(stepForeground(step.state))
        }
        .frame(width: badgeSize, height: badgeSize)
        .accessibilityLabel("Step \(step.number): \(step.title)")
    }

    private func stepForeground(_ state: ImportWorkflowStep.State) -> Color {
        switch state {
        case .complete:
            Color.accentColor
        case .current:
            Color.white
        case .upcoming:
            Color.accentColor.opacity(0.7)
        }
    }

    private func stepBackground(_ state: ImportWorkflowStep.State) -> Color {
        switch state {
        case .complete:
            Color.accentColor.opacity(0.18)
        case .current:
            Color.accentColor
        case .upcoming:
            Color.secondary.opacity(0.12)
        }
    }

    private func stepConnector(from previous: ImportWorkflowStep.State) -> some View {
        Capsule()
            .fill(previous == .complete ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.22))
            .frame(height: connectorHeight)
            .padding(.horizontal, 4)
    }
}

private struct PayeeNoteEditContext: Identifiable {
    let matchKey: String
    let samplePayee: String
    let autoGeneratedName: String

    var id: String { matchKey }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ImportRowHeader: View {
    let showsSelection: Bool

    var body: some View {
        HStack(spacing: 12) {
            if showsSelection {
                Text("Select")
                    .frame(width: 28)
            }
            Text("Date")
                .frame(width: 90, alignment: .leading)
            Text("Payee")
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            Text("Subcategory")
                .frame(width: 110, alignment: .leading)
            Text("Type")
                .frame(width: 110, alignment: .leading)
            Text("Category")
                .frame(width: 110, alignment: .leading)
            Text("Amount")
                .frame(width: 90, alignment: .trailing)
            Text("")
                .frame(width: 56)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct ImportTransactionRowView: View {
    @Binding var row: ImportPreviewRow
    let currency: AppCurrency
    let payeeNoteIndex: [String: PayeeNote]
    let showsSelection: Bool
    let isSelectable: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onImport: () -> Void
    let onCreateRecurringRule: () -> Void
    let onRemove: () -> Void
    let onEditPayeeNote: () -> Void

    private var dateText: String {
        row.transaction.date.formatted(date: .abbreviated, time: .omitted)
    }

    private var payeeLabels: (title: String, subtitle: String?) {
        PayeeNoteService.resolvedPayeeLabels(for: row.transaction.payee, in: payeeNoteIndex)
    }

    private var selectionHelpText: String {
        if isSelected { return "Deselect" }
        switch row.budgetType {
        case .income: return "Select to group as monthly income"
        case .expense: return "Select to group as monthly bill"
        case .saving: return "Select to group as monthly saving"
        default: return "Select to group as recurring"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if isSelectable {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 28)
                .help(selectionHelpText)
            } else if showsSelection {
                Color.clear
                    .frame(width: 28)
            }

            Text(dateText)
                .font(.caption)
                .frame(width: 90, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(payeeLabels.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Button(action: onEditPayeeNote) {
                        Image(systemName: "pencil")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Edit payee label & notes")
                }
                if let subtitle = payeeLabels.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(row.transaction.subcategory)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            Text(row.transaction.subcategory)
                .font(.caption)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)

            Picker("Type", selection: $row.budgetType) {
                ForEach(BudgetType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            .frame(width: 110)

            TextField("Category", text: $row.category)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)

            Text(MoneyFormatter.format(minorUnits: row.transaction.amountMinorUnits, currency: currency))
                .font(.body.monospacedDigit())
                .frame(width: 90, alignment: .trailing)

            HStack(spacing: 4) {
                Button(action: onImport) {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Import as one-off tile in this transaction's month")

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Exclude from import")
            }
            .frame(width: 56)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contextMenu {
            Button("Import as one-off tile", systemImage: "square.and.arrow.down") {
                onImport()
            }
            Button("Create recurring budget rule", systemImage: "arrow.triangle.2.circlepath") {
                onCreateRecurringRule()
            }
            Button("Edit payee label & notes", systemImage: "pencil") {
                onEditPayeeNote()
            }
            Button("Exclude from import", systemImage: "xmark.circle") {
                onRemove()
            }
        }
    }
}

private struct ExcludedTransactionRowView: View {
    let row: ImportPreviewRow
    let currency: AppCurrency
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(row.transaction.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .frame(width: 90, alignment: .leading)

            Text(row.transaction.payee)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(MoneyFormatter.format(minorUnits: row.transaction.amountMinorUnits, currency: currency))
                .font(.caption.monospacedDigit())
                .frame(width: 90, alignment: .trailing)

            Button {
                onRestore()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
            }
            .buttonStyle(.plain)
            .help("Restore to import list")
            .frame(width: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(.secondary)
    }
}
