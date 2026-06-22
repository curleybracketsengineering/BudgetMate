import SwiftData
import SwiftUI

struct HolidayTripDayScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query private var tiles: [BudgetTile]

    let holiday: Holiday
    @Binding var copiedActivityID: UUID?
    @Binding var selectedActivityID: UUID?
    @Binding var pasteTargetDate: Date?
    @Binding var pasteTargetTripDay: Int?
    var onKeyboardFocus: () -> Void = {}
    var includedActivityIDs: Set<UUID>? = nil
    var stopLookup: [UUID: HolidayItineraryService.MapStop] = [:]
    var highlightedTripDay: Int?
    var onEditActivity: ((HolidayActivity) -> Void)?

    @State private var addActivityContext: HolidayAddActivityContext?
    @State private var activityPendingDeletion: HolidayActivity?

    private var currency: AppCurrency { settingsList.first?.currency ?? .GBP }

    var body: some View {
        let tripLayout = HolidayService.tripDaySections(
            for: holiday,
            includingActivityIDs: includedActivityIDs
        )

        Group {
            if let tripLayout {
                let sections = tripLayout.0
                let unscheduled = tripLayout.unscheduled
                let lastDay = sections.last?.day

                let scrollAnchors = tripDayScrollAnchors(
                    sections: sections,
                    hasUnscheduled: !unscheduled.isEmpty
                )

                VStack(alignment: .leading, spacing: 0) {
                    if !unscheduled.isEmpty {
                        unscheduledSection(unscheduled)
                            .id(TripDayScrollAnchor.unscheduled)
                    }

                    ForEach(sections) { section in
                        daySection(section, lastDay: lastDay, sections: sections)
                            .id(TripDayScrollAnchor.day(section.day))
                    }
                }
                .scrollTargetLayout()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                .preference(key: TripDayScrollAnchorsKey.self, value: scrollAnchors)
            } else {
                Text("Set a trip start date to organize activities by day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .preference(key: TripDayScrollAnchorsKey.self, value: [])
            }
        }
        .sheet(item: $addActivityContext) { context in
            HolidayActivityFormView(
                currency: currency,
                holiday: holiday,
                initialStartDate: context.initialStartDate,
                initialKind: context.initialKind
            )
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
    }

    @ViewBuilder
    private func unscheduledSection(_ activities: [HolidayActivity]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Unscheduled", subtitle: nil, isHighlighted: false)
                .contextMenu {
                    Button {
                        addActivityContext = HolidayAddActivityContext()
                    } label: {
                        Label("Add activity", systemImage: "plus")
                    }
                }

            if activities.isEmpty {
                emptyDropRow(message: "No unscheduled activities")
                    .contextMenu {
                        Button {
                            addActivityContext = HolidayAddActivityContext()
                        } label: {
                            Label("Add activity", systemImage: "plus")
                        }
                    }
            } else {
                ForEach(activities, id: \.id) { activity in
                    activityRow(activity, mapStop: stopLookup[activity.id])
                    if activity.id != activities.last?.id {
                        Divider().padding(.leading, 36)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func daySection(
        _ section: HolidayService.TripDaySection,
        lastDay: Int?,
        sections: [HolidayService.TripDaySection]
    ) -> some View {
        let isHighlighted = highlightedTripDay == section.day
        let startDayActivities = section.activitiesStartingOnDay
        let startDayActivityIDs = Set(startDayActivities.map(\.id))

        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "Day \(section.day)",
                subtitle: section.date.formatted(date: .abbreviated, time: .omitted),
                isHighlighted: isHighlighted
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectPasteTarget(tripDay: section.day, date: section.date)
            }
            .contextMenu {
                Button {
                    addActivityContext = HolidayAddActivityContext(initialStartDate: section.date)
                } label: {
                    Label("Add activity", systemImage: "plus")
                }
                if copiedActivity() != nil {
                    Button {
                        pasteActivity(toTripDay: section.day)
                    } label: {
                        Label("Paste activity", systemImage: "doc.on.clipboard")
                    }
                    .keyboardShortcut("v", modifiers: .command)
                }
            }

            if section.activities.isEmpty {
                emptyDropRow(message: "Drop activities here")
                    .dropDestination(for: String.self) { items, _ in
                        handleDrop(items, toTripDay: section.day, atIndex: 0, sections: sections)
                    }
                    .contextMenu {
                        Button {
                            addActivityContext = HolidayAddActivityContext(initialStartDate: section.date)
                        } label: {
                            Label("Add activity", systemImage: "plus")
                        }
                        if copiedActivity() != nil {
                            Button {
                                pasteActivity(toTripDay: section.day)
                            } label: {
                                Label("Paste activity", systemImage: "doc.on.clipboard")
                            }
                            .keyboardShortcut("v", modifiers: .command)
                        }
                    }
            } else {
                ForEach(Array(section.activities.enumerated()), id: \.element.id) { _, activity in
                    let isStartDay = startDayActivityIDs.contains(activity.id)
                    let dropIndex = startDayActivities.firstIndex(where: { $0.id == activity.id })

                    Group {
                        if isStartDay, let dropIndex {
                            activityRow(
                                activity,
                                mapStop: stopLookup[activity.id],
                                tripDay: section.day,
                                isStartDay: true
                            )
                            .dropDestination(for: String.self) { items, _ in
                                handleDrop(items, toTripDay: section.day, atIndex: dropIndex, sections: sections)
                            }
                        } else {
                            activityRow(
                                activity,
                                mapStop: stopLookup[activity.id],
                                tripDay: section.day,
                                isStartDay: isStartDay
                            )
                        }
                    }

                    if activity.id != section.activities.last?.id {
                        Divider().padding(.leading, 36)
                    }
                }

                emptyDropRow(message: "Drop at end of day")
                    .dropDestination(for: String.self) { items, _ in
                        handleDrop(
                            items,
                            toTripDay: section.day,
                            atIndex: startDayActivities.count,
                            sections: sections
                        )
                    }
                    .contextMenu {
                        Button {
                            addActivityContext = HolidayAddActivityContext(initialStartDate: section.date)
                        } label: {
                            Label("Add activity", systemImage: "plus")
                        }
                        if copiedActivity() != nil {
                            Button {
                                pasteActivity(toTripDay: section.day)
                            } label: {
                                Label("Paste activity", systemImage: "doc.on.clipboard")
                            }
                            .keyboardShortcut("v", modifiers: .command)
                        }
                    }
            }
        }
        .dropDestination(for: String.self) { items, _ in
            handleDrop(
                items,
                toTripDay: section.day,
                atIndex: startDayActivities.count,
                sections: sections
            )
        }

        if section.day != lastDay {
            Divider()
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String?, isHighlighted: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if isHighlighted {
                Color.accentColor.opacity(0.12)
            } else {
                Color.primary.opacity(0.06)
            }
        }
    }

    @ViewBuilder
    private func emptyDropRow(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.dashed")
                .foregroundStyle(.tertiary)
                .frame(width: 20)
            Text(message)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func activityRow(
        _ activity: HolidayActivity,
        mapStop: HolidayItineraryService.MapStop?,
        tripDay: Int? = nil,
        isStartDay: Bool = true
    ) -> some View {
        let isSelected = selectedActivityID == activity.id
        let durationLabel = tripDay.flatMap {
            HolidayService.tripDayDurationLabel(activity: activity, holiday: holiday, tripDay: $0)
        }

        let rowContent = HStack(spacing: 10) {
            if isStartDay {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                    .accessibilityLabel("Drag to move")
            } else {
                Color.clear.frame(width: 16)
            }

            if let mapStop {
                Text("\(mapStop.order)")
                    .font(.caption.weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(mapStopCircleColor(for: mapStop), in: Circle())
                    .foregroundStyle(.white)
            }

            Image(systemName: activity.kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                if let mapStop, !mapStop.locationName.isEmpty {
                    Text(mapStop.locationName)
                        .font(.subheadline.weight(.medium))
                }
                Text(activity.name)
                    .font(mapStop == nil ? .subheadline.weight(.medium) : .caption)
                    .foregroundStyle(isStartDay ? .primary : .secondary)
                    .lineLimit(2)

                if let routeSummary = HolidayTravelEstimateService.routeSummaryLabel(
                    activity: activity,
                    holiday: holiday
                ) {
                    HStack(spacing: 6) {
                        Text(routeSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if activity.kind == .driving {
                            HolidayDrivingRouteButton(activity: activity, holiday: holiday)
                        }
                    }
                } else if activity.kind == .driving {
                    HolidayDrivingRouteButton(activity: activity, holiday: holiday)
                }

                if mapStop == nil, let durationLabel {
                    Text(durationLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let onEditActivity {
                Button {
                    onEditActivity(activity)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }

        Group {
            if isStartDay {
                rowContent
                    .draggable(activity.id.uuidString)
            } else {
                rowContent
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .opacity(isStartDay ? 1 : 0.85)
        .contentShape(Rectangle())
        .onActivitySelectionTap(
            onSelect: { selectActivity(activity) },
            onEdit: { onEditActivity?(activity) }
        )
        .contextMenu {
            if let onEditActivity {
                Button {
                    onEditActivity(activity)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
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
            }
            Button(role: .destructive) {
                activityPendingDeletion = activity
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func tripDayScrollAnchors(
        sections: [HolidayService.TripDaySection],
        hasUnscheduled: Bool
    ) -> [TripDayScrollAnchor] {
        var anchors: [TripDayScrollAnchor] = []
        if hasUnscheduled {
            anchors.append(.unscheduled)
        }
        anchors.append(contentsOf: sections.map { .day($0.day) })
        return anchors
    }

    private func mapStopCircleColor(for stop: HolidayItineraryService.MapStop) -> Color {
        if let highlightedTripDay, stop.isActive(onTripDay: highlightedTripDay) {
            return .accentColor
        }
        if highlightedTripDay != nil {
            return .gray.opacity(0.55)
        }
        return .accentColor
    }

    @discardableResult
    private func handleDrop(
        _ items: [String],
        toTripDay day: Int,
        atIndex index: Int,
        sections: [HolidayService.TripDaySection]
    ) -> Bool {
        guard let idString = items.first,
              let id = UUID(uuidString: idString),
              let activity = holiday.activities.first(where: { $0.id == id }) else {
            return false
        }

        if let includedActivityIDs, !includedActivityIDs.contains(id) {
            return false
        }

        if let tripStart = holiday.plannedStartDate,
           let currentStart = HolidayService.resolvedStartDate(activity: activity, holiday: holiday) {
            let currentDay = HolidayItineraryService.tripDay(for: currentStart, tripStart: tripStart)
            let currentIndex = sections
                .first(where: { $0.day == currentDay })?
                .activitiesStartingOnDay
                .firstIndex(where: { $0.id == id })
            if currentDay == day, currentIndex == index {
                return false
            }
        }

        HolidayService.repositionActivity(
            activity,
            toTripDay: day,
            atIndex: index,
            holiday: holiday
        )

        do {
            try modelContext.save()
            return true
        } catch {
            print("Trip day schedule save failed: \(error)")
            return false
        }
    }

    private func selectPasteTarget(tripDay: Int, date: Date) {
        pasteTargetTripDay = tripDay
        pasteTargetDate = date
        onKeyboardFocus()
    }

    private func selectActivity(_ activity: HolidayActivity) {
        selectedActivityID = activity.id
        pasteTargetDate = HolidayService.resolvedStartDate(activity: activity, holiday: holiday)
        if let tripStart = holiday.plannedStartDate,
           let activityStart = pasteTargetDate {
            pasteTargetTripDay = HolidayItineraryService.tripDay(for: activityStart, tripStart: tripStart)
        }
        onKeyboardFocus()
    }

    private func copyActivity(_ activity: HolidayActivity) {
        selectActivity(activity)
        copiedActivityID = activity.id
    }

    private func copiedActivity() -> HolidayActivity? {
        guard let id = copiedActivityID else { return nil }
        return holiday.activities.first { $0.id == id }
    }

    private func pasteActivity(toTripDay day: Int) {
        guard let source = copiedActivity() else { return }
        if let includedActivityIDs, !includedActivityIDs.contains(source.id) {
            return
        }
        do {
            _ = try HolidayService.duplicateActivity(
                source,
                in: holiday,
                toTripDay: day,
                in: modelContext
            )
        } catch {
            print("Trip day schedule paste failed: \(error)")
        }
    }

    private func deleteActivity() {
        guard let activity = activityPendingDeletion else { return }
        do {
            try HolidayService.deleteActivity(activity, from: holiday, allTiles: tiles, in: modelContext)
        } catch {
            print("Trip day schedule delete failed: \(error)")
        }
        activityPendingDeletion = nil
    }
}
