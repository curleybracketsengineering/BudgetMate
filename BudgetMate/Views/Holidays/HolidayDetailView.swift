import SwiftUI
import SwiftData

struct HolidayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query private var months: [BudgetMonth]
    @Query private var tiles: [BudgetTile]

    let holiday: Holiday
    var onDeleted: () -> Void

    @State private var showingEditHoliday = false
    @State private var addActivityContext: HolidayAddActivityContext?
    @State private var editingActivity: HolidayActivity?
    @State private var activityPendingDeletion: HolidayActivity?
    @State private var commitError: String?
    @State private var showingCommitError = false
    @State private var activityListLayout: HolidayActivityListLayout = .byType
    @State private var isInteractingWithMap = false
    @State private var copiedActivityID: UUID?
    @State private var selectedActivityID: UUID?
    @State private var pasteTargetDate: Date?
    @State private var pasteTargetTripDay: Int?
    @State private var tripDayScrollAnchors: [TripDayScrollAnchor] = []
    @State private var tripDayScrollPosition: TripDayScrollAnchor?
    @State private var pendingTripDayScroll: Int?
    @State private var pinnedTopControlsHeight: CGFloat = 0
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

    private var availableActivityListLayouts: [HolidayActivityListLayout] {
        HolidayActivityListLayout.allCases.filter { layout in
            layout != .map || showsMapPage
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                if activityListLayout == .map {
                    mapContent
                } else {
                    planContent
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsPinnedTopControls {
                pinnedTopControls
            }
        }
        .scrollPosition(id: $tripDayScrollPosition, anchor: .top)
        .onScrollTargetVisibilityChange(idType: TripDayScrollAnchor.self) { visibleIDs in
            guard let topmost = visibleIDs.first else { return }
            tripDayScrollPosition = topmost
        }
        .overlay {
            if !tripDayScrollAnchors.isEmpty {
                DragAutoScrollOverlay(
                    scrollIDs: tripDayScrollAnchors,
                    scrollPosition: $tripDayScrollPosition,
                    excludedTopHeight: pinnedTopControlsHeight
                )
            }
        }
        .onPreferenceChange(TripDayScrollAnchorsKey.self) { anchors in
            tripDayScrollAnchors = anchors
            scrollToPendingTripDayIfNeeded(using: anchors)
        }
        .onChange(of: activityListLayout) { _, layout in
            if layout != .byDay {
                tripDayScrollAnchors = []
                pendingTripDayScroll = nil
            } else {
                scrollToPendingTripDayIfNeeded(using: tripDayScrollAnchors)
            }
        }
        .scrollDisabled(isInteractingWithMap && activityListLayout == .map)
        .onChange(of: showsMapPage) { _, hasMap in
            if !hasMap, activityListLayout == .map {
                activityListLayout = .byType
            }
        }
        .onChange(of: showsPinnedTopControls) { _, shows in
            if !shows {
                pinnedTopControlsHeight = 0
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
            HStack(spacing: 8) {
                Button {
                    addActivityContext = HolidayAddActivityContext()
                } label: {
                    Label("Add activity", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button("Edit trip") {
                    showingEditHoliday = true
                }
                .buttonStyle(.bordered)

                Spacer()
            }

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

    private var showsPinnedTopControls: Bool {
        !holiday.activities.isEmpty || showsMapPage
    }

    @ViewBuilder
    private var pinnedTopControls: some View {
        VStack(spacing: 0) {
            if showsPinnedTopControls {
                Picker("Layout", selection: $activityListLayout) {
                    ForEach(availableActivityListLayouts) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()
            }
        }
        .background(.background)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            pinnedTopControlsHeight = height
        }
    }

    @ViewBuilder
    private var planContent: some View {
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
                        onKeyboardFocus: { holidayKeyboardFocused = true },
                        onOpenDaySchedule: openDaySchedule
                    ) { activity in
                        editingActivity = activity
                    }
                case .map:
                    EmptyView()
                }
            }
        }
    }

    private enum ActivityRowLeading {
        case none
        case kind
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
    private func activityRow(
        _ activity: HolidayActivity,
        leading: ActivityRowLeading
    ) -> some View {
        let dateLabel = HolidayService.activityDateRangeLabel(activity: activity, holiday: holiday)
        let plannedMonth = HolidayService.resolvedPlannedMonth(activity: activity, holiday: holiday)
        let routeSummary = HolidayTravelEstimateService.routeSummaryLabel(activity: activity, holiday: holiday)
        let isSelected = selectedActivityID == activity.id

        HStack(alignment: .top, spacing: 10) {
            switch leading {
            case .kind:
                Image(systemName: activity.kind.systemImage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
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
                if routeSummary != nil || activity.kind == .driving {
                    HStack(spacing: 6) {
                        if let routeSummary {
                            Text(routeSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if activity.kind == .driving {
                            HolidayDrivingRouteButton(activity: activity, holiday: holiday)
                        }
                    }
                }
                HStack(spacing: 6) {
                    if let dateLabel {
                        Label(dateLabel, systemImage: "calendar")
                    } else if let plannedMonth {
                        Text(HolidayService.monthTitle(year: plannedMonth.year, month: plannedMonth.month))
                    }
                    if activity.kind.supportsMultiDayDuration, activity.nights > 0 {
                        if dateLabel != nil || plannedMonth != nil {
                            Text("·")
                        }
                        Text(activity.kind.durationLabel(count: activity.nights))
                    }
                    if let note = activity.estimateNote.nilIfEmpty {
                        if dateLabel != nil || plannedMonth != nil || (activity.kind.supportsMultiDayDuration && activity.nights > 0) {
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
        .onActivitySelectionTap(
            onSelect: { selectActivity(activity) },
            onEdit: { editingActivity = activity }
        )
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
        if (activityListLayout == .byDay || activityListLayout == .map), let pasteTargetTripDay,
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

    private func openDaySchedule(for date: Date) {
        let dayStart = Calendar.current.startOfDay(for: date)
        pasteTargetDate = dayStart
        if let tripStart = holiday.plannedStartDate {
            let tripDay = HolidayItineraryService.tripDay(for: dayStart, tripStart: tripStart)
            pasteTargetTripDay = tripDay
            pendingTripDayScroll = tripDay
        }
        activityListLayout = .byDay
        holidayKeyboardFocused = true
        scrollToPendingTripDayIfNeeded(using: tripDayScrollAnchors)
    }

    private func scrollToPendingTripDayIfNeeded(using anchors: [TripDayScrollAnchor]) {
        guard let tripDay = pendingTripDayScroll else { return }
        let anchor = TripDayScrollAnchor.day(tripDay)
        guard anchors.contains(anchor) else { return }
        tripDayScrollPosition = anchor
        pendingTripDayScroll = nil
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

        if (activityListLayout == .byDay || activityListLayout == .map), let pasteTargetTripDay {
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
