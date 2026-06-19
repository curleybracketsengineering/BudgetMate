import SwiftUI
import SwiftData

struct DatabaseSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var summary: DatabaseSummary?
    @State private var loadError: String?
    @State private var recoveryMessage: String?

    var body: some View {
        List {
            if let summary {
                storageSection(summary)
                overviewSection(summary)
                rulesSection(summary)
                tilesSection(summary)
                if !summary.sampleActiveRuleNames.isEmpty {
                    sampleRulesSection(summary)
                }
                if !summary.sampleArchivedRuleNames.isEmpty {
                    archivedRulesSection(summary)
                }
            } else if let loadError {
                Text(loadError)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Loading…")
            }
        }
        .navigationTitle("Data Summary")
        .toolbar {
            ToolbarItem {
                Button {
                    reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { reload() }
        .alert("Data restored", isPresented: recoveryAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recoveryMessage ?? "")
        }
    }

    @ViewBuilder
    private func storageSection(_ summary: DatabaseSummary) -> some View {
        Section("Storage") {
            LabeledContent("Active database", value: summary.activeStoreName)
            if let alternateCount = summary.alternateStoreRuleCount {
                LabeledContent(summary.alternateStoreName, value: "\(alternateCount) rules")
            }
            if summary.canRecoverFromAlternateStore {
                Button("Restore missing data from alternate store") {
                    recoverFromAlternateStore()
                }
                Text("Your app is using a smaller database copy. The alternate store has more rules and can be merged in.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var recoveryAlertPresented: Binding<Bool> {
        Binding(
            get: { recoveryMessage != nil },
            set: { if !$0 { recoveryMessage = nil } }
        )
    }

    private func recoverFromAlternateStore() {
        do {
            guard let result = try StoreRecoveryService.recoverFromAlternateStoreIfNeeded(
                in: modelContext,
                activeConfiguration: ModelContainerFactory.activeConfiguration
            ), result.didRecover else {
                recoveryMessage = "No additional data was found to restore."
                return
            }
            recoveryMessage = """
            Restored \(result.rulesAdded) rules, \(result.tilesAdded) tiles, and \(result.monthsAdded) months \
            from your \(result.source == .cloud ? "iCloud" : "local") database.
            """
            reload()
        } catch {
            recoveryMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func overviewSection(_ summary: DatabaseSummary) -> some View {
        Section("Overview") {
            if let planningPeriodLabel = summary.planningPeriodLabel {
                LabeledContent("Planning period", value: planningPeriodLabel)
            }
            LabeledContent("Bank accounts", value: "\(summary.accountCount)")
            LabeledContent("Plan months", value: "\(summary.monthCount)")
            LabeledContent("Payee notes", value: "\(summary.payeeNoteCount)")
            if summary.holidayCount > 0 {
                LabeledContent("Holidays", value: "\(summary.holidayCount)")
            }
            if summary.subCategoryCount > 0 {
                LabeledContent("Rule sub-categories", value: "\(summary.subCategoryCount)")
            }
        }
    }

    @ViewBuilder
    private func rulesSection(_ summary: DatabaseSummary) -> some View {
        Section("Budget rules") {
            LabeledContent("Total", value: "\(summary.totalRules)")
            LabeledContent("Active", value: "\(summary.activeRules)")
            LabeledContent("Archived", value: "\(summary.archivedRules)")
            LabeledContent("Incoming", value: "\(summary.incomingRules)")
            LabeledContent("Outgoing", value: "\(summary.outgoingRules)")
            if summary.otherRules > 0 {
                LabeledContent("Transfers & adjustments", value: "\(summary.otherRules)")
            }

            ForEach(summary.rulesByType) { item in
                LabeledContent(item.type.displayName, value: "\(item.count)")
            }
        }
    }

    @ViewBuilder
    private func tilesSection(_ summary: DatabaseSummary) -> some View {
        Section("Budget tiles") {
            LabeledContent("Total", value: "\(summary.totalTiles)")
            LabeledContent("Active", value: "\(summary.activeTiles)")
            LabeledContent("In planning period", value: "\(summary.tilesInHorizon)")
            if summary.tilesOutsideHorizon > 0 {
                LabeledContent("Outside planning period", value: "\(summary.tilesOutsideHorizon)")
                    .foregroundStyle(.orange)
            }

            ForEach(summary.tilesBySource) { item in
                LabeledContent(item.source.displayName, value: "\(item.count)")
            }
        }
    }

    @ViewBuilder
    private func sampleRulesSection(_ summary: DatabaseSummary) -> some View {
        Section("Active rules (sample)") {
            ForEach(summary.sampleActiveRuleNames, id: \.self) { name in
                Text(name)
                    .font(.subheadline)
            }
            if summary.activeRules > summary.sampleActiveRuleNames.count {
                Text("+ \(summary.activeRules - summary.sampleActiveRuleNames.count) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func archivedRulesSection(_ summary: DatabaseSummary) -> some View {
        Section("Archived rules") {
            ForEach(summary.sampleArchivedRuleNames, id: \.self) { name in
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func reload() {
        do {
            summary = try DatabaseSummaryService.fetch(in: modelContext)
            loadError = nil
        } catch {
            summary = nil
            loadError = error.localizedDescription
        }
    }
}
