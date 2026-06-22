import SwiftUI
import SwiftData

struct HolidayAddActivityContext: Identifiable {
    let id = UUID()
    var initialStartDate: Date?
    var initialKind: HolidayActivityKind?
}

struct HolidayActivityFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BudgetRuleSubCategory.sortOrder) private var allSubCategories: [BudgetRuleSubCategory]

    let currency: AppCurrency
    let holiday: Holiday
    var existingActivity: HolidayActivity?
    var initialStartDate: Date?
    var initialKind: HolidayActivityKind?

    @State private var name = ""
    @State private var kind: HolidayActivityKind = .other
    @State private var amountText = ""
    @State private var notes = ""
    @State private var subCategory: BudgetRuleSubCategory?
    @State private var linkedAccountId: UUID?
    @State private var fromLocationName = ""
    @State private var locationName = ""
    @State private var countryName = ""
    @State private var distanceText = ""
    @State private var durationText = ""
    @State private var travelEstimatesAreManual = false
    @State private var isEstimatingTravel = false
    @State private var travelEstimateTask: Task<Void, Never>?
    @State private var isApplyingAutoEstimate = false
    @State private var nights = 0
    @State private var useCustomMonth = false
    @State private var plannedMonth = Calendar.current.component(.month, from: .now)
    @State private var plannedYear = Calendar.current.component(.year, from: .now)
    @State private var hasSpecificDates = false
    @State private var startDate = Date.now
    @State private var hasEndDate = false
    @State private var endDate = Date.now

    private var calendar: Calendar { Calendar.current }

    private var durationEndDate: Date? {
        guard kind.supportsMultiDayDuration, nights > 0 else { return nil }
        return calendar.date(byAdding: .day, value: nights - 1, to: calendar.startOfDay(for: startDate))
    }

    private var tripHasStartDate: Bool {
        holiday.plannedStartDate != nil
    }

    private var showsDatePickers: Bool {
        tripHasStartDate || hasSpecificDates
    }

    private var showsTravelEstimateSection: Bool {
        kind.hasFromToFields && (kind.showsDistanceEstimate || kind.showsTravelDurationEstimate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    Picker("Type", selection: $kind) {
                        ForEach(HolidayActivityKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    .onChange(of: kind) { _, newKind in
                        if newKind.supportsMultiDayDuration {
                            if nights < 1 {
                                nights = 1
                            }
                            syncDurationEndDate()
                        } else {
                            nights = 0
                        }
                        if newKind.hasFromToFields {
                            if !newKind.showsDistanceEstimate {
                                distanceText = ""
                            }
                            if !newKind.showsTravelDurationEstimate {
                                durationText = ""
                            }
                            scheduleTravelEstimate()
                        } else {
                            travelEstimateTask?.cancel()
                            isEstimatingTravel = false
                        }
                    }
                    TextField("Name", text: $name)
                    if kind.hasFromToFields {
                        TextField("From", text: $fromLocationName, prompt: Text("Departure city or place"))
                            .onChange(of: fromLocationName) { _, _ in
                                locationsDidChange()
                            }
                        TextField("To", text: $locationName, prompt: Text("Arrival city or place (e.g. Cape Town)"))
                            .onChange(of: locationName) { _, _ in
                                locationsDidChange()
                            }
                    } else {
                        TextField("Location", text: $locationName, prompt: Text("City or place (e.g. Cape Town)"))
                    }
                    TextField("Country", text: $countryName, prompt: Text("Optional — uses trip country if empty"))
                        .onChange(of: countryName) { _, _ in
                            if kind.hasFromToFields {
                                locationsDidChange()
                            }
                        }
                    TextField("Amount", text: $amountText)
                }

                if showsTravelEstimateSection {
                    Section("Travel estimate") {
                        if isEstimatingTravel {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Calculating estimate…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if kind.showsDistanceEstimate {
                            TextField("Distance (miles)", text: $distanceText, prompt: Text("e.g. 142"))
                                .onChange(of: distanceText) { _, _ in
                                    markTravelEstimatesManual()
                                }
                        }

                        if kind.showsTravelDurationEstimate {
                            TextField(
                                kind == .flights ? "Flight time" : "Drive time",
                                text: $durationText,
                                prompt: Text("e.g. 2h 30m")
                            )
                            .onChange(of: durationText) { _, _ in
                                markTravelEstimatesManual()
                            }
                        }

                        if kind == .driving {
                            HolidayDrivingRouteButton(
                                origin: fromLocationName,
                                destination: locationName,
                                countryName: resolvedCountryNameForEstimate(),
                                style: .labeled
                            )
                        }

                        if !travelEstimatesAreManual,
                           !distanceText.isEmpty || !durationText.isEmpty || isEstimatingTravel {
                            Text("Estimated from the route. You can edit these values.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Category") {
                    BudgetRuleSubCategoryPicker(
                        selectedSubCategory: $subCategory,
                        orderGroup: .outgoing
                    )
                    AccountPicker(linkedAccountId: $linkedAccountId)
                }

                Section("Planned month") {
                    Toggle("Custom month", isOn: $useCustomMonth)
                    if useCustomMonth {
                        PlanningStartPicker(
                            month: $plannedMonth,
                            year: $plannedYear,
                            label: "Show in"
                        )
                    } else {
                        Text("Uses the trip default or start date month.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Dates") {
                    if showsDatePickers {
                        DatePicker(
                            kind.durationStartDateLabel,
                            selection: $startDate,
                            displayedComponents: .date
                        )
                        .onChange(of: startDate) { _, _ in
                            if kind.supportsMultiDayDuration {
                                syncDurationEndDate()
                            } else if hasEndDate, endDate < startDate {
                                endDate = startDate
                            }
                        }

                        if kind.supportsMultiDayDuration {
                            FormIntegerStepper(kind.durationStepperLabel, value: $nights, in: 1...60) { count in
                                kind.durationLabel(count: count)
                            }
                            .onChange(of: nights) { _, _ in
                                syncDurationEndDate()
                            }
                            if let durationEndDate {
                                LabeledContent(kind.durationEndDateLabel) {
                                    Text(durationEndDate.formatted(date: .abbreviated, time: .omitted))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Toggle("Multi-day", isOn: $hasEndDate)
                            if hasEndDate {
                                DatePicker(
                                    "Ends",
                                    selection: $endDate,
                                    in: startDate...,
                                    displayedComponents: .date
                                )
                            }
                        }
                    } else {
                        Toggle("Specific dates", isOn: $hasSpecificDates)
                        if hasSpecificDates {
                            DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                                .onChange(of: startDate) { _, _ in
                                    if hasEndDate, endDate < startDate {
                                        endDate = startDate
                                    }
                                }
                            Toggle("Multi-day", isOn: $hasEndDate)
                            if hasEndDate {
                                DatePicker(
                                    "Ends",
                                    selection: $endDate,
                                    in: startDate...,
                                    displayedComponents: .date
                                )
                            }
                        } else {
                            Text("Set a trip start date, or turn on specific dates.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(4...12)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existingActivity == nil ? "Add Activity" : "Edit Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isEstimatingTravel
                    )
                }
            }
            .onAppear {
                if let existingActivity {
                    loadExisting(from: existingActivity)
                } else {
                    loadNewActivityDefaults()
                }
                scheduleTravelEstimate()
            }
            .onDisappear {
                travelEstimateTask?.cancel()
            }
        }
        .frame(minWidth: 420, minHeight: 480)
    }

    private func loadExisting(from activity: HolidayActivity) {
        name = activity.name
        kind = activity.kind
        fromLocationName = activity.fromLocationName
        locationName = activity.locationName
        countryName = activity.countryName
        travelEstimatesAreManual = activity.travelEstimatesAreManual
        distanceText = HolidayTravelEstimateService.formatDistanceMiles(km: activity.estimatedDistanceKm)
        if activity.estimatedDurationMinutes > 0 {
            durationText = HolidayTravelEstimateService.formatDuration(minutes: activity.estimatedDurationMinutes)
        } else if let inferredMinutes = HolidayTravelEstimateService.inferDurationMinutes(from: activity.name) {
            durationText = HolidayTravelEstimateService.formatDuration(minutes: inferredMinutes)
            travelEstimatesAreManual = true
        } else {
            durationText = ""
        }
        nights = activity.nights
        amountText = MoneyFormatter.majorUnitsString(minorUnits: activity.amountMinorUnits, currency: currency)
        notes = activity.notes
        subCategory = activity.subCategoryId.flatMap { id in
            allSubCategories.first { $0.id == id }
        }
        linkedAccountId = activity.linkedAccountId
        if activity.plannedYear > 0, activity.plannedMonth > 0 {
            useCustomMonth = true
            plannedYear = activity.plannedYear
            plannedMonth = activity.plannedMonth
        }
        applyResolvedDates(
            start: activity.plannedStartDate
                ?? HolidayService.resolvedStartDate(activity: activity, holiday: holiday),
            end: activity.plannedEndDate
                ?? HolidayService.resolvedEndDate(activity: activity, holiday: holiday)
        )
        if kind.supportsMultiDayDuration, nights < 1 {
            nights = inferredNights(from: startDate, end: endDate, hasEndDate: hasEndDate)
        }
    }

    private func loadNewActivityDefaults() {
        if let initialKind {
            kind = initialKind
            if initialKind.supportsMultiDayDuration {
                nights = 1
            }
        }
        if let initialStartDate {
            applyResolvedDates(start: initialStartDate, end: initialStartDate)
            let components = calendar.dateComponents([.year, .month], from: initialStartDate)
            if let year = components.year, let month = components.month {
                plannedYear = year
                plannedMonth = month
            }
        } else if let tripStart = holiday.plannedStartDate {
            applyResolvedDates(start: tripStart, end: tripStart)
        }
    }

    private func applyResolvedDates(start: Date?, end: Date?) {
        guard let start else { return }
        hasSpecificDates = true
        startDate = start
        if kind.supportsMultiDayDuration {
            if nights < 1 {
                let spansMultipleDays = end.map { !calendar.isDate($0, inSameDayAs: start) } ?? false
                nights = inferredNights(from: start, end: end, hasEndDate: spansMultipleDays)
            }
            syncDurationEndDate()
            return
        }

        if let end, !calendar.isDate(end, inSameDayAs: start) {
            hasEndDate = true
            endDate = end
        } else if nights > 1 {
            hasEndDate = true
            endDate = calendar.date(byAdding: .day, value: nights - 1, to: start) ?? start
        } else {
            hasEndDate = false
            endDate = start
        }
    }

    private func inferredNights(from start: Date, end: Date?, hasEndDate: Bool) -> Int {
        guard hasEndDate, let end else { return 1 }
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let daySpan = (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
        return max(daySpan, 1)
    }

    private func syncDurationEndDate() {
        guard kind.supportsMultiDayDuration else { return }
        if nights > 1 {
            hasEndDate = true
            endDate = calendar.date(byAdding: .day, value: nights - 1, to: calendar.startOfDay(for: startDate)) ?? startDate
        } else {
            hasEndDate = false
            endDate = startDate
        }
    }

    private func save() async {
        travelEstimateTask?.cancel()
        if showsTravelEstimateSection, !travelEstimatesAreManual {
            await refreshTravelEstimateIfNeeded()
        }

        let activity = existingActivity ?? HolidayActivity()
        if existingActivity == nil {
            activity.markCreated()
            activity.sortOrder = (holiday.activities.map(\.sortOrder).max() ?? -1) + 1
            activity.holiday = holiday
            modelContext.insert(activity)
        }

        activity.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        activity.kind = kind
        let trimmedFrom = fromLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedFrom != activity.fromLocationName
            || trimmedLocation != activity.locationName
            || trimmedCountry != activity.countryName {
            activity.clearGeocodeCache()
        }
        activity.fromLocationName = trimmedFrom
        activity.locationName = trimmedLocation
        activity.countryName = trimmedCountry
        activity.travelEstimatesAreManual = travelEstimatesAreManual
        if kind.showsDistanceEstimate {
            activity.estimatedDistanceKm = HolidayTravelEstimateService.parseDistanceMiles(distanceText) ?? 0
        } else {
            activity.estimatedDistanceKm = 0
        }
        if kind.showsTravelDurationEstimate {
            activity.estimatedDurationMinutes = HolidayTravelEstimateService.parseDuration(durationText) ?? 0
        } else {
            activity.estimatedDurationMinutes = 0
        }
        activity.nights = kind.supportsMultiDayDuration ? max(nights, 1) : 0
        activity.amountMinorUnits = MoneyFormatter.parseMajorUnits(amountText, currency: currency) ?? 0
        activity.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        activity.subCategoryId = subCategory?.id
        activity.linkedAccountId = linkedAccountId
        if useCustomMonth {
            activity.plannedYear = plannedYear
            activity.plannedMonth = plannedMonth
        } else {
            activity.plannedYear = 0
            activity.plannedMonth = 0
        }
        if showsDatePickers {
            activity.plannedStartDate = calendar.startOfDay(for: startDate)
            if kind.supportsMultiDayDuration {
                if nights > 1 {
                    activity.plannedEndDate = calendar.date(byAdding: .day, value: nights - 1, to: calendar.startOfDay(for: startDate))
                } else {
                    activity.plannedEndDate = nil
                }
            } else if hasEndDate {
                activity.plannedEndDate = calendar.startOfDay(for: endDate)
            } else {
                activity.plannedEndDate = nil
            }
            activity.estimateSource = .manual
        } else {
            activity.plannedStartDate = nil
            activity.plannedEndDate = nil
        }
        activity.markUpdated()
        holiday.markUpdated()

        do {
            try modelContext.save()
            if holiday.status == .committed {
                let settings = try AppDataService.ensureSettings(in: modelContext)
                let months = try AppDataService.fetchMonths(settings: settings, in: modelContext)
                let tiles = try AppDataService.fetchAllTiles(in: modelContext)
                try HolidayService.syncCommittedHoliday(
                    holiday: holiday,
                    settings: settings,
                    months: months,
                    allTiles: tiles,
                    in: modelContext
                )
            }
            dismiss()
        } catch {
            print("Activity save failed: \(error)")
        }
    }

    private func locationsDidChange() {
        travelEstimatesAreManual = false
        scheduleTravelEstimate()
    }

    private func markTravelEstimatesManual() {
        guard !isApplyingAutoEstimate else { return }
        travelEstimatesAreManual = true
    }

    private func scheduleTravelEstimate() {
        travelEstimateTask?.cancel()
        guard showsTravelEstimateSection, !travelEstimatesAreManual else { return }

        let from = fromLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else { return }

        let country = resolvedCountryNameForEstimate()
        let activityKind = kind

        travelEstimateTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }

            await MainActor.run { isEstimatingTravel = true }
            let estimate = await HolidayTravelEstimateService.estimate(
                kind: activityKind,
                fromLocationName: from,
                toLocationName: to,
                countryName: country
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                isEstimatingTravel = false
                guard let estimate, !travelEstimatesAreManual else { return }
                applyTravelEstimate(estimate)
            }
        }
    }

    private func resolvedCountryNameForEstimate() -> String {
        let activityCountry = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !activityCountry.isEmpty { return activityCountry }

        let holidayCountry = holiday.countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !holidayCountry.isEmpty { return holidayCountry }

        return ""
    }

    private func applyTravelEstimate(_ estimate: HolidayTravelEstimateService.Estimate) {
        isApplyingAutoEstimate = true
        defer { isApplyingAutoEstimate = false }

        if kind.showsDistanceEstimate, let distanceKm = estimate.distanceKm {
            distanceText = HolidayTravelEstimateService.formatDistanceMiles(km: distanceKm)
        }
        if kind.showsTravelDurationEstimate, let durationMinutes = estimate.durationMinutes {
            durationText = HolidayTravelEstimateService.formatDuration(minutes: durationMinutes)
        }
    }

    private func refreshTravelEstimateIfNeeded() async {
        let from = fromLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else { return }

        let needsDistance = kind.showsDistanceEstimate && distanceText.isEmpty
        let needsDuration = kind.showsTravelDurationEstimate && durationText.isEmpty
        guard needsDistance || needsDuration else { return }

        isEstimatingTravel = true
        defer { isEstimatingTravel = false }

        let estimate = await HolidayTravelEstimateService.estimate(
            kind: kind,
            fromLocationName: from,
            toLocationName: to,
            countryName: resolvedCountryNameForEstimate()
        )
        guard !travelEstimatesAreManual, let estimate else { return }
        applyTravelEstimate(estimate)
    }
}
