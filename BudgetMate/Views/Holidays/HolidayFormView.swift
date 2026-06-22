import SwiftUI
import SwiftData

struct HolidayFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let currency: AppCurrency
    var existingHoliday: Holiday?
    var onSave: ((Holiday) -> Void)?

    private static let durationPresets = [7, 10, 14, 18]
    private static let maxCustomDuration = 90

    @State private var name = ""
    @State private var origin = ""
    @State private var destination = ""
    @State private var countryName = ""
    @State private var tripDescription = ""
    @State private var notes = ""
    @State private var hasStartDate = false
    @State private var startDate = Date.now
    @State private var usesManualEndDate = false
    @State private var endDate = Date.now.addingTimeInterval(86400 * 7)
    @State private var selectedDurationPreset = 10
    @State private var customDurationDays = 10
    @State private var defaultPlannedMonth = Calendar.current.component(.month, from: .now)
    @State private var defaultPlannedYear = Calendar.current.component(.year, from: .now)
    @State private var useDefaultMonth = false
    @State private var showingDateValidationAlert = false

    private var calendar: Calendar { Calendar.current }

    private var effectiveDurationDays: Int {
        if selectedDurationPreset == -1 {
            return max(1, min(customDurationDays, Self.maxCustomDuration))
        }
        return selectedDurationPreset
    }

    private var computedEndDate: Date {
        endDateFromDuration(start: startDate, days: effectiveDurationDays)
    }

    private var resolvedEndDate: Date? {
        guard hasStartDate else { return nil }
        if usesManualEndDate {
            return endDate
        }
        return computedEndDate
    }

    private var datesAreValid: Bool {
        guard hasStartDate, let end = resolvedEndDate else { return true }
        return calendar.startOfDay(for: end) >= calendar.startOfDay(for: startDate)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && datesAreValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    TextField("Name", text: $name)
                    TextField("Origin (optional)", text: $origin)
                    TextField("Destination", text: $destination)
                    TextField("Country (for map)", text: $countryName, prompt: Text("e.g. South Africa"))
                }

                Section("Dates") {
                    Toggle("Start date", isOn: $hasStartDate)
                    if hasStartDate {
                        DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                            .onChange(of: startDate) { _, _ in
                                syncEndDateFromDuration()
                                clampManualEndDate()
                            }

                        Toggle("Pick end date manually", isOn: $usesManualEndDate)

                        if usesManualEndDate {
                            DatePicker(
                                "Ends",
                                selection: $endDate,
                                in: startDate...,
                                displayedComponents: .date
                            )
                        } else {
                            Picker("Trip length", selection: $selectedDurationPreset) {
                                ForEach(Self.durationPresets, id: \.self) { days in
                                    Text("\(days) days").tag(days)
                                }
                                Text("Custom").tag(-1)
                            }
                            .onChange(of: selectedDurationPreset) { _, _ in
                                syncEndDateFromDuration()
                            }

                            if selectedDurationPreset == -1 {
                                Stepper(
                                    "\(effectiveDurationDays) days",
                                    value: $customDurationDays,
                                    in: 1...Self.maxCustomDuration
                                )
                                .onChange(of: customDurationDays) { _, _ in
                                    syncEndDateFromDuration()
                                }
                            }

                            LabeledContent("Ends") {
                                Text(computedEndDate.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !datesAreValid {
                            Label("End date must be on or after the start date.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("Monthly plan") {
                    Toggle("Default planned month", isOn: $useDefaultMonth)
                    if useDefaultMonth {
                        PlanningStartPicker(
                            month: $defaultPlannedMonth,
                            year: $defaultPlannedYear,
                            label: "Show costs in"
                        )
                    }
                    Text("Activities inherit this month unless they specify their own.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextEditor(text: $tripDescription)
                        .frame(minHeight: 100)
                } header: {
                    Text("Description")
                } footer: {
                    Text("Overview of the trip — useful for import from description and your own reference.")
                        .font(.caption)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existingHoliday == nil ? "New Holiday" : "Edit Holiday")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { loadExisting() }
            .onChange(of: hasStartDate) { _, isOn in
                if isOn { syncEndDateFromDuration() }
            }
            .onChange(of: usesManualEndDate) { _, manual in
                if manual {
                    clampManualEndDate()
                } else {
                    syncEndDateFromDuration()
                }
            }
            .alert("Invalid dates", isPresented: $showingDateValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The end date must be on or after the start date.")
            }
        }
        .frame(minWidth: 440, minHeight: 640)
    }

    private func loadExisting() {
        guard let holiday = existingHoliday else { return }
        name = holiday.name
        origin = holiday.origin
        destination = holiday.destination
        countryName = holiday.countryName
        tripDescription = holiday.tripDescription
        notes = holiday.notes
        if let start = holiday.plannedStartDate {
            hasStartDate = true
            startDate = start
        }
        if let end = holiday.plannedEndDate {
            endDate = max(end, startDate)
            let days = inclusiveDayCount(from: startDate, to: endDate)
            if Self.durationPresets.contains(days) {
                selectedDurationPreset = days
                usesManualEndDate = false
            } else {
                selectedDurationPreset = -1
                customDurationDays = days
                usesManualEndDate = false
            }
        }
        if holiday.defaultPlannedYear > 0, holiday.defaultPlannedMonth > 0 {
            useDefaultMonth = true
            defaultPlannedYear = holiday.defaultPlannedYear
            defaultPlannedMonth = holiday.defaultPlannedMonth
        }
    }

    private func save() {
        guard datesAreValid else {
            showingDateValidationAlert = true
            return
        }

        let holiday = existingHoliday ?? Holiday()
        if existingHoliday == nil {
            holiday.markCreated()
            modelContext.insert(holiday)
        }

        holiday.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        holiday.origin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        holiday.destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCountry != holiday.countryName {
            for activity in holiday.activities {
                activity.clearGeocodeCache()
            }
        }
        holiday.countryName = trimmedCountry
        holiday.tripDescription = tripDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        holiday.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        holiday.plannedStartDate = hasStartDate ? calendar.startOfDay(for: startDate) : nil
        holiday.plannedEndDate = hasStartDate ? calendar.startOfDay(for: resolvedEndDate ?? startDate) : nil
        if useDefaultMonth {
            holiday.defaultPlannedYear = defaultPlannedYear
            holiday.defaultPlannedMonth = defaultPlannedMonth
        } else {
            holiday.defaultPlannedYear = 0
            holiday.defaultPlannedMonth = 0
        }
        holiday.markUpdated()

        do {
            if existingHoliday == nil {
                try HolidayService.assignDisplayOrderForNewHoliday(holiday, in: modelContext)
            }
            try modelContext.save()
            onSave?(holiday)
            dismiss()
        } catch {
            print("Holiday save failed: \(error)")
        }
    }

    private func syncEndDateFromDuration() {
        guard hasStartDate, !usesManualEndDate else { return }
        endDate = computedEndDate
    }

    private func clampManualEndDate() {
        guard usesManualEndDate, endDate < startDate else { return }
        endDate = startDate
    }

    /// Inclusive day count: same start and end = 1 day.
    private func inclusiveDayCount(from start: Date, to end: Date) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let dayDelta = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(dayDelta + 1, 1)
    }

    private func endDateFromDuration(start: Date, days: Int) -> Date {
        let startDay = calendar.startOfDay(for: start)
        return calendar.date(byAdding: .day, value: max(days, 1) - 1, to: startDay) ?? startDay
    }
}
