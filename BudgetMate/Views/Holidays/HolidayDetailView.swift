import SwiftUI
import SwiftData

struct HolidayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(TravelSearchStore.self) private var travelSearch
    @Query private var settingsList: [AppSettings]
    @Query private var months: [BudgetMonth]
    @Query private var tiles: [BudgetTile]

    let holiday: Holiday
    var onDeleted: () -> Void

    @State private var showingEditHoliday = false
    @State private var showingAddActivity = false
    @State private var editingActivity: HolidayActivity?
    @State private var activityPendingDeletion: HolidayActivity?
    @State private var commitError: String?
    @State private var showingCommitError = false

    private var currency: AppCurrency { settingsList.first?.currency ?? .GBP }
    private var summary: HolidayService.Summary { HolidayService.summary(for: holiday) }

    private var kindsWithActivities: [HolidayActivityKind] {
        HolidayActivityKind.allCases.filter { kind in
            holiday.sortedActivities.contains { $0.kind == kind }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                travelSearchSection
                activitiesSection
                totalSection
                commitSection
            }
            .padding()
        }
        .navigationTitle(holiday.name.isEmpty ? "Holiday" : holiday.name)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingEditHoliday) {
            HolidayFormView(currency: currency, existingHoliday: holiday)
        }
        .sheet(isPresented: $showingAddActivity) {
            HolidayActivityFormView(currency: currency, holiday: holiday)
        }
        .sheet(item: $editingActivity) { activity in
            HolidayActivityFormView(currency: currency, holiday: holiday, existingActivity: activity)
        }
        .confirmationDialog(
            "Delete activity?",
            isPresented: Binding(
                get: { activityPendingDeletion != nil },
                set: { if !$0 { activityPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteActivity()
            }
        }
        .alert("Could not add to plan", isPresented: $showingCommitError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(commitError ?? "")
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !holiday.destination.isEmpty || !holiday.origin.isEmpty {
                Label(
                    [holiday.origin, holiday.destination].filter { !$0.isEmpty }.joined(separator: " → "),
                    systemImage: "mappin.and.ellipse"
                )
                .foregroundStyle(.secondary)
            }
            if let dates = holiday.dateRangeLabel {
                Label(dates, systemImage: "calendar")
                    .foregroundStyle(.secondary)
            }
            if holiday.status == .committed {
                Label("In monthly plan", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.medium))
            }
            if !holiday.notes.isEmpty {
                Text(holiday.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var travelSearchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Find prices")
                .font(.headline)
            Text("Open a travel site with your trip details pre-filled, then copy amounts back into activities.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                searchButton("Flights", systemImage: "airplane") {
                    openSearch(kind: .flights)
                }
                searchButton("Hotels", systemImage: "bed.double") {
                    openSearch(kind: .hotels)
                }
                searchButton("Car hire", systemImage: "car") {
                    openSearch(kind: .carHire)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activities")
                    .font(.headline)
                Spacer()
                Button {
                    showingAddActivity = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }

            if holiday.activities.isEmpty {
                ContentUnavailableView(
                    "No activities",
                    systemImage: "list.bullet",
                    description: Text("Add flights, hotels, and other costs for this trip.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(kindsWithActivities, id: \.self) { kind in
                    activityGroup(
                        kind: kind,
                        activities: holiday.sortedActivities.filter { $0.kind == kind }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func activityGroup(kind: HolidayActivityKind, activities: [HolidayActivity]) -> some View {
        let subtotal = activities.reduce(0) { $0 + $1.amountMinorUnits }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(kind.displayName, systemImage: kind.systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(MoneyFormatter.format(minorUnits: subtotal, currency: currency))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5))

            ForEach(activities, id: \.id) { activity in
                activityRow(activity)
                Divider()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    @ViewBuilder
    private func activityRow(_ activity: HolidayActivity) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if let planned = HolidayService.resolvedPlannedMonth(activity: activity, holiday: holiday) {
                        Text(HolidayService.monthTitle(year: planned.year, month: planned.month))
                    }
                    if let note = activity.estimateNote.nilIfEmpty {
                        Text("·")
                        Text(note)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(MoneyFormatter.format(minorUnits: activity.amountMinorUnits, currency: currency))
                .font(.body.monospacedDigit())
            Menu {
                Button("Edit") { editingActivity = activity }
                Button("Delete", role: .destructive) {
                    activityPendingDeletion = activity
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var totalSection: some View {
        HStack {
            Text("Total")
                .font(.title3.weight(.semibold))
            Spacer()
            Text(MoneyFormatter.format(minorUnits: summary.totalMinorUnits, currency: currency))
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .padding()
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var commitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if holiday.defaultPlannedYear > 0, holiday.defaultPlannedMonth > 0 {
                Label(
                    "Default month: \(HolidayService.monthTitle(year: holiday.defaultPlannedYear, month: holiday.defaultPlannedMonth))",
                    systemImage: "calendar.badge.clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if holiday.status == .draft {
                Button {
                    commitToPlan()
                } label: {
                    Label("Add to Monthly Plan", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(holiday.activities.isEmpty)
            } else {
                Button {
                    uncommitFromPlan()
                } label: {
                    Label("Remove from Monthly Plan", systemImage: "calendar.badge.minus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Edit trip") {
                showingEditHoliday = true
            }
        }
    }

    private func searchButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private enum SearchKind {
        case flights, hotels, carHire
    }

    private func openSearch(kind: SearchKind) {
        let url: URL?
        switch kind {
        case .flights:
            url = TravelDeepLinkService.flightSearchURL(
                provider: travelSearch.flightSearchProvider,
                origin: holiday.origin,
                destination: holiday.destination,
                startDate: holiday.plannedStartDate,
                endDate: holiday.plannedEndDate
            )
        case .hotels:
            url = TravelDeepLinkService.hotelSearchURL(
                provider: travelSearch.hotelSearchProvider,
                destination: holiday.destination,
                startDate: holiday.plannedStartDate,
                endDate: holiday.plannedEndDate
            )
        case .carHire:
            url = TravelDeepLinkService.carHireSearchURL(
                provider: travelSearch.carHireSearchProvider,
                destination: holiday.destination,
                startDate: holiday.plannedStartDate,
                endDate: holiday.plannedEndDate
            )
        }
        guard let url else { return }
        openURL(url)
    }

    private func commitToPlan() {
        do {
            let settings = try AppDataService.ensureSettings(in: modelContext)
            let planMonths = try AppDataService.fetchMonths(settings: settings, in: modelContext)
            let allTiles = try AppDataService.fetchAllTiles(in: modelContext)
            try HolidayService.commit(
                holiday: holiday,
                settings: settings,
                months: planMonths,
                allTiles: allTiles,
                in: modelContext
            )
        } catch {
            commitError = error.localizedDescription
            showingCommitError = true
        }
    }

    private func uncommitFromPlan() {
        do {
            let allTiles = try AppDataService.fetchAllTiles(in: modelContext)
            try HolidayService.uncommit(holiday: holiday, allTiles: allTiles, in: modelContext)
        } catch {
            commitError = error.localizedDescription
            showingCommitError = true
        }
    }

    private func deleteActivity() {
        guard let activity = activityPendingDeletion else { return }
        if let tile = tiles.first(where: { $0.linkedHolidayActivityId == activity.id }) {
            modelContext.delete(tile)
        }
        modelContext.delete(activity)
        holiday.markUpdated()
        do {
            try modelContext.save()
            if holiday.status == .committed {
                let settings = try AppDataService.ensureSettings(in: modelContext)
                let planMonths = try AppDataService.fetchMonths(settings: settings, in: modelContext)
                let allTiles = try AppDataService.fetchAllTiles(in: modelContext)
                try HolidayService.syncCommittedHoliday(
                    holiday: holiday,
                    settings: settings,
                    months: planMonths,
                    allTiles: allTiles,
                    in: modelContext
                )
            } else {
                try AppDataService.refreshForecast(in: modelContext)
            }
        } catch {
            print("Delete activity failed: \(error)")
        }
        activityPendingDeletion = nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
