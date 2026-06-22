import SwiftUI
import SwiftData

struct HolidayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(TravelSearchStore.self) private var travelSearch
    @Environment(FeatureGateService.self) private var featureGate
    @Query private var settingsList: [AppSettings]
    @Query private var months: [BudgetMonth]
    @Query private var tiles: [BudgetTile]

    let holiday: Holiday
    var onDeleted: () -> Void

    @State private var showingEditHoliday = false
    @State private var addActivityContext: HolidayAddActivityContext?
    @State private var showingImportDescription = false
    @State private var editingActivity: HolidayActivity?
    @State private var activityPendingDeletion: HolidayActivity?
    @State private var commitError: String?
    @State private var showingCommitError = false
    @State private var activityListLayout: HolidayActivityListLayout = .byType
    @State private var detailPage: HolidayDetailPage = .plan
    @State private var isInteractingWithMap = false
    @State private var copiedActivityID: UUID?
    @State private var selectedActivityID: UUID?
    @State private var pasteTargetDate: Date?
    @State private var pasteTargetTripDay: Int?
    @FocusState private var holidayKeyboardFocused: Bool

    private var currency: AppCurrency { settingsList.first?.currency ?? .GBP }
    private var summary: HolidayService.Summary { HolidayService.summary(for: holiday) }

    private var kindsWithActivities: [HolidayActivityKind] {
        HolidayActivityKind.allCases.filter { kind in
            holiday.sortedActivities.contains { $0.kind == kind }
        }
    }

    private var showsMapPage: Bool {
        HolidayItineraryService.hasMappableContent(for: holiday)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                if showsMapPage {
                    detailPagePicker
                }
                switch detailPage {
                case .plan:
                    planContent
                case .map:
                    mapContent
                }
            }
            .padding()
        }
        .scrollDisabled(isInteractingWithMap && detailPage == .map)
        .onChange(of: showsMapPage) { _, hasMap in
            if !hasMap {
                detailPage = .plan
            }
        }
        .holidayActivityKeyboardShortcuts(
            isFocused: $holidayKeyboardFocused,
            canCopy: selectedActivityID != nil,
            canPaste: canPasteFromKeyboard,
            onCopy: copyFromKeyboard,
            onPaste: pasteFromKeyboard
        )
        .navigationTitle(holiday.name.isEmpty ? "Holiday" : holiday.name)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingEditHoliday) {
            HolidayFormView(currency: currency, existingHoliday: holiday)
        }
        .sheet(item: $addActivityContext) { context in
            HolidayActivityFormView(
                currency: currency,
                holiday: holiday,
                initialStartDate: context.initialStartDate,
                initialKind: context.initialKind
            )
        }
        .sheet(item: $editingActivity) { activity in
            HolidayActivityFormView(currency: currency, holiday: holiday, existingActivity: activity)
        }
        .sheet(isPresented: $showingImportDescription) {
            HolidayDescriptionImportView(currency: currency, holiday: holiday)
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
            if !holiday.tripDescription.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HolidayMarkdownText(holiday.tripDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !holiday.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HolidayMarkdownText(holiday.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var detailPagePicker: some View {
        Picker("View", selection: $detailPage) {
            ForEach(HolidayDetailPage.allCases) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var planContent: some View {
        travelSearchSection
        activitiesSection
        totalSection
        commitSection
    }

    @ViewBuilder
    private var mapContent: some View {
        HolidayTripMapView(
            holiday: holiday,
            isInteractingWithMap: $isInteractingWithMap,
            copiedActivityID: $copiedActivityID,
            selectedActivityID: $selectedActivityID,
            pasteTargetDate: $pasteTargetDate,
            pasteTargetTripDay: $pasteTargetTripDay,
            onKeyboardFocus: { holidayKeyboardFocused = true }
        )
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
                    addActivityContext = HolidayAddActivityContext()
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }

            if !holiday.activities.isEmpty {
                Picker("Layout", selection: $activityListLayout) {
                    ForEach(HolidayActivityListLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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
                switch activityListLayout {
                case .byType:
                    ForEach(kindsWithActivities, id: \.self) { kind in
                        activityGroup(
                            kind: kind,
                            activities: holiday.sortedActivities.filter { $0.kind == kind }
                        )
                    }
                case .byDate:
                    chronologicalActivityList
                case .byDay:
                    HolidayTripDayScheduleView(
                        holiday: holiday,
                        copiedActivityID: $copiedActivityID,
                        selectedActivityID: $selectedActivityID,
                        pasteTargetDate: $pasteTargetDate,
                        pasteTargetTripDay: $pasteTargetTripDay,
                        onKeyboardFocus: { holidayKeyboardFocused = true }
                    ) { activity in
                        editingActivity = activity
                    }
                case .calendar:
                    HolidayActivityCalendarView(
                        holiday: holiday,
                        copiedActivityID: $copiedActivityID,
                        selectedActivityID: $selectedActivityID,
                        pasteTargetDate: $pasteTargetDate,
                        onKeyboardFocus: { holidayKeyboardFocused = true }
                    ) { activity in
                        editingActivity = activity
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var chronologicalActivityList: some View {
        let activities = HolidayService.chronologicallySortedActivities(for: holiday)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(activities, id: \.id) { activity in
                activityRow(activity, leading: .date)
                if activity.id != activities.last?.id {
                    Divider()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .contextMenu {
            Button {
                addActivityContext = HolidayAddActivityContext()
            } label: {
                Label("Add activity", systemImage: "plus")
            }
        }
    }

    private enum ActivityRowLeading {
        case none
        case kind
        case date
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
            .contextMenu {
                Button {
                    addActivityContext = HolidayAddActivityContext(initialKind: kind)
                } label: {
                    Label("Add \(kind.displayName)", systemImage: "plus")
                }
            }

            ForEach(activities, id: \.id) { activity in
                activityRow(activity, leading: .none)
                Divider()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    @ViewBuilder
    private func activityRow(_ activity: HolidayActivity, leading: ActivityRowLeading) -> some View {
        let dateLabel = HolidayService.activityDateRangeLabel(activity: activity, holiday: holiday)
        let compactDateParts = HolidayService.activityCompactDateParts(activity: activity, holiday: holiday)
        let plannedMonth = HolidayService.resolvedPlannedMonth(activity: activity, holiday: holiday)
        let showsInlineDate = leading != .date
        let expandsEditableFields = leading != .date
        let isSelected = selectedActivityID == activity.id

        HStack(alignment: .top, spacing: 10) {
            switch leading {
            case .kind:
                Image(systemName: activity.kind.systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            case .date:
                activityDateColumn(compactDateParts: compactDateParts, plannedMonth: plannedMonth)
            case .none:
                EmptyView()
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    InlineEditableText(
                        text: activity.name,
                        placeholder: "Name",
                        font: .body,
                        weight: .medium,
                        expandsHorizontally: expandsEditableFields,
                        onCommit: { newName in
                            guard !newName.isEmpty else { return }
                            activity.name = newName
                            persistActivityChange(activity)
                        }
                    )
                    if activity.estimateSource == .aiSuggested {
                        Text("AI suggested")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 6) {
                    if showsInlineDate {
                        if let dateLabel {
                            Label(dateLabel, systemImage: "calendar")
                        } else if let plannedMonth {
                            Text(HolidayService.monthTitle(year: plannedMonth.year, month: plannedMonth.month))
                        }
                    }
                    if activity.kind == .hotels, activity.nights > 0 {
                        if showsInlineDate && (dateLabel != nil || plannedMonth != nil) {
                            Text("·")
                        }
                        Text(activity.nights == 1 ? "1 night" : "\(activity.nights) nights")
                    }
                    if let note = activity.estimateNote.nilIfEmpty {
                        if showsInlineDate && (dateLabel != nil || plannedMonth != nil || (activity.kind == .hotels && activity.nights > 0)) {
                            Text("·")
                        }
                        Text(note)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                InlineEditableText(
                    text: activity.notes,
                    placeholder: "Add notes…",
                    font: .caption,
                    isSecondary: true,
                    lineLimit: 3,
                    multiline: true,
                    expandsHorizontally: expandsEditableFields,
                    onCommit: { newNotes in
                        activity.notes = newNotes
                        persistActivityChange(activity)
                    }
                )
            }
            Spacer()
            InlineEditableAmount(
                minorUnits: activity.amountMinorUnits,
                currency: currency,
                onCommit: { newAmount in
                    activity.amountMinorUnits = newAmount
                    if activity.estimateSource == .aiSuggested {
                        activity.estimateSource = .manual
                    }
                    persistActivityChange(activity)
                }
            )
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
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                selectActivity(activity)
            }
        )
        .onTapGesture(count: 2) {
            editingActivity = activity
        }
        .contextMenu {
            activityRowContextMenu(for: activity)
        }
    }

    @ViewBuilder
    private func activityRowContextMenu(for activity: HolidayActivity) -> some View {
        Button {
            editingActivity = activity
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button {
            copyActivity(activity)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .keyboardShortcut("c", modifiers: .command)
        if let start = HolidayService.resolvedStartDate(activity: activity, holiday: holiday) {
            Button {
                addActivityContext = HolidayAddActivityContext(initialStartDate: start)
            } label: {
                Label("Add activity on this date", systemImage: "plus")
            }
            if copiedActivity() != nil {
                Button {
                    pasteActivity(onto: start)
                } label: {
                    Label("Paste activity", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("v", modifiers: .command)
            }
        }
        Button(role: .destructive) {
            activityPendingDeletion = activity
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func activityDateColumn(
        compactDateParts: HolidayService.ActivityCompactDateParts?,
        plannedMonth: (year: Int, month: Int)?
    ) -> some View {
        Group {
            if let compactDateParts {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(compactDateParts.topLine)
                        .font(.caption.weight(.semibold))
                    Text(compactDateParts.bottomLine)
                        .font(.caption2)
                }
            } else if let plannedMonth {
                Text(HolidayService.monthTitle(year: plannedMonth.year, month: plannedMonth.month))
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.trailing)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: 52, alignment: .trailing)
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
            Menu {
                Button {
                    addActivityContext = HolidayAddActivityContext()
                } label: {
                    Label("Add activity", systemImage: "plus")
                }
                if featureGate.isAvailable(.holidayPlanner) {
                    Button {
                        showingImportDescription = true
                    } label: {
                        Label("Import from description", systemImage: "sparkles")
                    }
                    .disabled(HolidayDescriptionImportService.availabilityMessage() != nil)
                }
                Button("Edit trip") {
                    showingEditHoliday = true
                }
            } label: {
                Label("Trip actions", systemImage: "ellipsis.circle")
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

    private func persistActivityChange(_ activity: HolidayActivity) {
        activity.markUpdated()
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
            }
        } catch {
            print("Activity update failed: \(error)")
        }
    }

    private var canPasteFromKeyboard: Bool {
        copiedActivity() != nil && effectivePasteTargetDate != nil
    }

    private var effectivePasteTargetDate: Date? {
        if (activityListLayout == .byDay || detailPage == .map), let pasteTargetTripDay,
           let tripStart = holiday.plannedStartDate {
            return HolidayItineraryService.date(forTripDay: pasteTargetTripDay, tripStart: tripStart)
        }
        if let pasteTargetDate {
            return pasteTargetDate
        }
        guard let selectedActivityID,
              let activity = holiday.activities.first(where: { $0.id == selectedActivityID }) else {
            return nil
        }
        return HolidayService.resolvedStartDate(activity: activity, holiday: holiday)
    }

    private func selectActivity(_ activity: HolidayActivity) {
        selectedActivityID = activity.id
        pasteTargetDate = HolidayService.resolvedStartDate(activity: activity, holiday: holiday)
        if let tripStart = holiday.plannedStartDate,
           let activityStart = pasteTargetDate {
            pasteTargetTripDay = HolidayItineraryService.tripDay(for: activityStart, tripStart: tripStart)
        }
        holidayKeyboardFocused = true
    }

    private func copyActivity(_ activity: HolidayActivity) {
        selectActivity(activity)
        copiedActivityID = activity.id
    }

    private func copyFromKeyboard() {
        guard let selectedActivityID else { return }
        copiedActivityID = selectedActivityID
    }

    private func pasteFromKeyboard() {
        guard copiedActivity() != nil else { return }

        if (activityListLayout == .byDay || detailPage == .map), let pasteTargetTripDay {
            pasteActivity(toTripDay: pasteTargetTripDay)
            return
        }

        guard let dayStart = effectivePasteTargetDate else { return }
        pasteActivity(onto: dayStart)
    }

    private func copiedActivity() -> HolidayActivity? {
        guard let id = copiedActivityID else { return nil }
        return holiday.activities.first { $0.id == id }
    }

    private func pasteActivity(onto dayStart: Date) {
        guard let source = copiedActivity() else { return }
        do {
            _ = try HolidayService.duplicateActivity(
                source,
                in: holiday,
                ontoDay: dayStart,
                in: modelContext
            )
        } catch {
            print("Activity paste failed: \(error)")
        }
    }

    private func pasteActivity(toTripDay day: Int) {
        guard let source = copiedActivity() else { return }
        do {
            _ = try HolidayService.duplicateActivity(
                source,
                in: holiday,
                toTripDay: day,
                in: modelContext
            )
        } catch {
            print("Activity paste failed: \(error)")
        }
    }

    private func deleteActivity() {
        guard let activity = activityPendingDeletion else { return }
        do {
            try HolidayService.deleteActivity(activity, from: holiday, allTiles: tiles, in: modelContext)
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
