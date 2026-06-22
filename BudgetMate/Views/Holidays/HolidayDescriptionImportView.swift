import SwiftUI
import SwiftData

struct HolidayDescriptionImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(FeatureGateService.self) private var featureGate
    @Query private var tiles: [BudgetTile]

    let currency: AppCurrency
    let holiday: Holiday

    @State private var pastedText = ""
    @State private var metadata = HolidayTripMetadataDraft()
    @State private var drafts: [HolidayActivityImportDraft] = []
    @State private var replaceExisting = false
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var showingReplaceConfirmation = false
    @State private var expandedDraftID: UUID?

    private var includedCount: Int {
        drafts.filter(\.isIncluded).count
    }

    private var hasResults: Bool {
        !drafts.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if !featureGate.isAvailable(.holidayPlanner) {
                    PlaceholderSectionView(
                        title: "Pro feature",
                        message: "Importing trip descriptions from AI text is part of the Holiday & event planner.",
                        proFeature: .holidayPlanner
                    )
                } else if let availabilityMessage = HolidayDescriptionImportService.availabilityMessage(), !hasResults {
                    ContentUnavailableView {
                        Label("Apple Intelligence required", systemImage: "apple.intelligence.badge.xmark")
                    } description: {
                        Text(availabilityMessage)
                    }
                } else {
                    formContent
                }
            }
            .navigationTitle("Import from description")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if featureGate.isAvailable(.holidayPlanner), hasResults {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import \(includedCount)") {
                            if replaceExisting, !holiday.activities.isEmpty {
                                showingReplaceConfirmation = true
                            } else {
                                performImport()
                            }
                        }
                        .disabled(includedCount == 0)
                    }
                }
            }
            .alert("Import failed", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                "Replace existing activities?",
                isPresented: $showingReplaceConfirmation,
                titleVisibility: .visible
            ) {
                Button("Replace and import", role: .destructive) {
                    performImport()
                }
            } message: {
                Text("This removes all current activities for this trip and imports the selected items.")
            }
        }
        .frame(minWidth: 560, minHeight: 640)
        .onAppear {
            if pastedText.isEmpty, !holiday.tripDescription.isEmpty {
                pastedText = holiday.tripDescription
            }
        }
    }

    @ViewBuilder
    private var formContent: some View {
        Form {
            Section {
                Text("Paste a trip write-up from ChatGPT or another assistant. On-device Apple Intelligence will suggest activities per stop or leg for you to review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $pastedText)
                    .frame(minHeight: 160)
                    .font(.body)
                Button {
                    analyze()
                } label: {
                    if isAnalyzing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Analyzing…")
                        }
                    } else {
                        Label("Analyze", systemImage: "sparkles")
                    }
                }
                .disabled(isAnalyzing || pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Trip description")
            }

            if hasResults {
                metadataSection
                activitiesSection
                importOptionsSection
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var metadataSection: some View {
        Section("Trip details (optional)") {
            if metadata.applyName {
                Toggle("Update trip name", isOn: $metadata.applyName)
                TextField("Name", text: $metadata.name)
            }
            if metadata.applyOrigin {
                Toggle("Update origin", isOn: $metadata.applyOrigin)
                TextField("Origin", text: $metadata.origin)
            }
            if metadata.applyDestination {
                Toggle("Update destination", isOn: $metadata.applyDestination)
                TextField("Destination", text: $metadata.destination)
            }
            if metadata.applyDuration {
                Toggle("Update duration from nights", isOn: $metadata.applyDuration)
                Stepper("\(metadata.durationNights) nights", value: $metadata.durationNights, in: 1...90)
            }
            if !metadata.applyName, !metadata.applyOrigin, !metadata.applyDestination, !metadata.applyDuration {
                Text("No trip metadata was detected.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var activitiesSection: some View {
        Section("Suggested activities (\(includedCount) selected)") {
            ForEach($drafts) { $draft in
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $draft.isIncluded) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.name)
                                .font(.body.weight(.medium))
                            HStack(spacing: 6) {
                                Label(draft.kind.displayName, systemImage: draft.kind.systemImage)
                                if !draft.locationName.isEmpty {
                                    Text("·")
                                    Text(draft.locationName)
                                }
                                if draft.nights > 0 {
                                    Text("·")
                                    Text(draft.kind.durationLabel(count: draft.nights))
                                }
                                if !draft.amountText.isEmpty {
                                    Text("·")
                                    Text(draft.amountText)
                                        .monospacedDigit()
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    if expandedDraftID == draft.id {
                        Picker("Type", selection: $draft.kind) {
                            ForEach(HolidayActivityKind.allCases) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        TextField("Name", text: $draft.name)
                        if draft.kind.hasFromToFields {
                            TextField("From", text: $draft.fromLocationName)
                            TextField("To", text: $draft.locationName)
                        } else {
                            TextField("Location", text: $draft.locationName)
                        }
                        if draft.nights > 0 || draft.kind.supportsMultiDayDuration {
                            Stepper(draft.kind.durationLabel(count: draft.nights), value: $draft.nights, in: 0...60)
                        }
                        TextField("Amount", text: $draft.amountText)
                        if !draft.estimateNote.isEmpty {
                            Text(draft.estimateNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        TextField("Notes", text: $draft.notes, axis: .vertical)
                            .lineLimit(4...10)
                    }

                    Button(expandedDraftID == draft.id ? "Hide details" : "Edit details") {
                        withAnimation {
                            expandedDraftID = expandedDraftID == draft.id ? nil : draft.id
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var importOptionsSection: some View {
        Section("Import options") {
            Toggle("Replace all existing activities", isOn: $replaceExisting)
            if !replaceExisting {
                Text("New items will be added after your current activities.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func analyze() {
        isAnalyzing = true
        errorMessage = nil
        let text = pastedText

        Task {
            do {
                let result = try await HolidayDescriptionImportService.extract(
                    from: text,
                    currency: currency
                )
                await MainActor.run {
                    metadata = result.metadata
                    drafts = result.items
                    expandedDraftID = nil
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAnalyzing = false
                }
            }
        }
    }

    private func performImport() {
        do {
            let trimmedDescription = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDescription.isEmpty {
                holiday.tripDescription = trimmedDescription
            }
            try HolidayService.importActivities(
                drafts: drafts,
                into: holiday,
                metadata: metadata,
                replaceExisting: replaceExisting,
                currency: currency,
                allTiles: tiles,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
