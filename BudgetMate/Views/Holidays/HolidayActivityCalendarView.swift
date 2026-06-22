import SwiftData
import SwiftUI

struct HolidayActivityCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query private var tiles: [BudgetTile]

    let holiday: Holiday
    @Binding var copiedActivityID: UUID?
    @Binding var selectedActivityID: UUID?
    @Binding var pasteTargetDate: Date?
    var onKeyboardFocus: () -> Void = {}
    var onOpenDaySchedule: (Date) -> Void = { _ in }
    var onEditActivity: (HolidayActivity) -> Void

    @State private var dropTargetDate: Date?
    @State private var addActivityContext: HolidayAddActivityContext?
    @State private var activityPendingDeletion: HolidayActivity?
    @State private var dayCellHeight: CGFloat = Self.defaultDayCellHeight
    @State private var resizeDragStartHeight: CGFloat?

    private static let defaultDayCellHeight: CGFloat = 72
    private static let minDayCellHeight: CGFloat = 72
    private static let maxDayCellHeight: CGFloat = 220
    private static let activityRowHeight: CGFloat = 17
    private static let dayCellChromeHeight: CGFloat = 28

    private var currency: AppCurrency { settingsList.first?.currency ?? .GBP }
    private var calendar: Calendar { Calendar.current }
    private var months: [(year: Int, month: Int)] {
        HolidayService.calendarMonths(for: holiday)
    }

    var body: some View {
        Group {
            if months.isEmpty {
                ContentUnavailableView(
                    "No dates to show",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Set trip dates or add dates to activities to see the calendar.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    calendarResizeHandle

                    ForEach(Array(months.enumerated()), id: \.offset) { _, month in
                        monthGrid(year: month.year, month: month.month)
                    }
                }
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
    private func monthGrid(year: Int, month: Int) -> some View {
        let monthStart = PlanningCalendar.firstDayOfMonth(year: year, month: month)
        let monthTitle = HolidayService.monthTitle(year: year, month: month)
        let weekdaySymbols = calendar.shortWeekdaySymbols
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30

        VStack(alignment: .leading, spacing: 8) {
            Text(monthTitle)
                .font(.subheadline.weight(.semibold))

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: dayCellHeight)
                }

                ForEach(1...dayCount, id: \.self) { day in
                    dayCell(year: year, month: month, day: day)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    @ViewBuilder
    private func dayCell(year: Int, month: Int, day: Int) -> some View {
        let components = DateComponents(year: year, month: month, day: day)
        let date = calendar.date(from: components) ?? .now
        let dayStart = calendar.startOfDay(for: date)
        let activities = HolidayService.activities(on: dayStart, holiday: holiday)
        let startDayActivities = HolidayService.activitiesStarting(on: dayStart, holiday: holiday)
        let isToday = calendar.isDateInToday(dayStart)
        let isTripStart = holiday.plannedStartDate.map { calendar.isDate(dayStart, inSameDayAs: $0) } ?? false
        let isTripEnd = holiday.plannedEndDate.map { calendar.isDate(dayStart, inSameDayAs: $0) } ?? false
        let isDropTarget = dropTargetDate.map { calendar.isDate($0, inSameDayAs: dayStart) } ?? false
        let activityVisibility = visibleActivities(for: dayCellHeight, totalActivities: activities.count)
        let visibleActivitiesList = Array(activities.prefix(activityVisibility.visible))

        VStack(alignment: .leading, spacing: 3) {
            Text("\(day)")
                .font(.caption.weight(isToday || isTripStart || isTripEnd ? .bold : .regular))
                .foregroundStyle(isToday ? Color.accentColor : .primary)
                .contentShape(Rectangle())
                .onTapGesture {
                    openDaySchedule(dayStart)
                }

            ForEach(visibleActivitiesList, id: \.id) { activity in
                let isStartDay = HolidayService.isActivityStartDay(
                    activity: activity,
                    holiday: holiday,
                    day: dayStart
                )
                if isStartDay,
                   let dropIndex = startDayActivities.firstIndex(where: { $0.id == activity.id }) {
                    activityTile(activity, dayStart: dayStart, isDraggable: true)
                        .dropDestination(for: String.self) { items, _ in
                            handleDrop(items, onto: dayStart, atIndex: dropIndex)
                        }
                } else {
                    activityTile(activity, dayStart: dayStart, isDraggable: false)
                }
            }

            if activityVisibility.hidden > 0 {
                Button {
                    expandToShowActivities(count: activities.count)
                } label: {
                    Text("+\(activityVisibility.hidden) more")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: dayCellHeight, alignment: .topLeading)
        .padding(4)
        .background(
            isDropTarget
                ? Color.accentColor.opacity(0.15)
                : isTripStart || isTripEnd
                    ? Color.accentColor.opacity(0.08)
                    : Color.clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    isDropTarget ? Color.accentColor : isToday ? Color.accentColor.opacity(0.5) : .clear,
                    lineWidth: isDropTarget ? 2 : 1
                )
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                openDaySchedule(dayStart)
            } label: {
                Label("View day schedule", systemImage: "list.bullet.indent")
            }
            Button {
                addActivityContext = HolidayAddActivityContext(initialStartDate: dayStart)
            } label: {
                Label("Add activity", systemImage: "plus")
            }
            if copiedActivity() != nil {
                Button {
                    pasteActivity(onto: dayStart)
                } label: {
                    Label("Paste activity", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("v", modifiers: .command)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items, onto: dayStart, atIndex: startDayActivities.count)
        } isTargeted: { isTargeted in
            if isTargeted {
                dropTargetDate = dayStart
            } else if dropTargetDate.map({ calendar.isDate($0, inSameDayAs: dayStart) }) == true {
                dropTargetDate = nil
            }
        }
    }

    @ViewBuilder
    private func activityTile(_ activity: HolidayActivity, dayStart: Date, isDraggable: Bool) -> some View {
        let isSelected = selectedActivityID == activity.id
        let tile = HStack(spacing: 3) {
            Image(systemName: activity.kind.systemImage)
                .font(.system(size: 8))
            Text(activity.name)
                .lineLimit(1)
        }
        .font(.system(size: 9))
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(activityColor(for: activity.kind).opacity(isSelected ? 0.35 : 0.2), in: RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .foregroundStyle(activityColor(for: activity.kind))
        .contentShape(Rectangle())
        .onActivitySelectionTap(
            onSelect: { selectActivity(activity, defaultDay: dayStart) },
            onEdit: { onEditActivity(activity) }
        )
        .contextMenu {
            Button {
                selectActivity(activity, defaultDay: dayStart)
                onEditActivity(activity)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                copyActivity(activity)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: .command)
            Button(role: .destructive) {
                selectActivity(activity, defaultDay: dayStart)
                activityPendingDeletion = activity
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }

        if isDraggable {
            tile.draggable(activity.id.uuidString)
        } else {
            tile.opacity(isSelected ? 1 : 0.85)
        }
    }

    private var calendarResizeHandle: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.and.down")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Drag to resize day cells · Click a day to open its schedule")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(Int(dayCellHeight)) pt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.secondary.opacity(0.45))
                .frame(width: 40, height: 4)
                .padding(.bottom, 3)
        }
        .contentShape(Rectangle())
        .gesture(resizeDragGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Resize calendar day cells")
        .accessibilityValue("\(Int(dayCellHeight)) points")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                dayCellHeight = clampedDayCellHeight(dayCellHeight + Self.activityRowHeight)
            case .decrement:
                dayCellHeight = clampedDayCellHeight(dayCellHeight - Self.activityRowHeight)
            @unknown default:
                break
            }
        }
    }

    private var resizeDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if resizeDragStartHeight == nil {
                    resizeDragStartHeight = dayCellHeight
                }
                let base = resizeDragStartHeight ?? dayCellHeight
                dayCellHeight = clampedDayCellHeight(base + value.translation.height)
            }
            .onEnded { _ in
                resizeDragStartHeight = nil
            }
    }

    private static let overflowLabelHeight: CGFloat = 11

    private func visibleActivities(for cellHeight: CGFloat, totalActivities: Int) -> (visible: Int, hidden: Int) {
        let maxWithoutOverflow = max(
            1,
            Int(floor((cellHeight - Self.dayCellChromeHeight) / Self.activityRowHeight))
        )
        if totalActivities <= maxWithoutOverflow {
            return (totalActivities, 0)
        }

        let maxWithOverflow = max(
            1,
            Int(floor((cellHeight - Self.dayCellChromeHeight - Self.overflowLabelHeight) / Self.activityRowHeight))
        )
        let visible = min(maxWithOverflow, totalActivities)
        return (visible, totalActivities - visible)
    }

    private func heightForActivityCount(_ count: Int) -> CGFloat {
        Self.dayCellChromeHeight + CGFloat(count) * Self.activityRowHeight + 4
    }

    private func clampedDayCellHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, Self.minDayCellHeight), Self.maxDayCellHeight)
    }

    private func expandToShowActivities(count: Int) {
        dayCellHeight = clampedDayCellHeight(
            max(dayCellHeight, heightForActivityCount(count))
        )
    }

    private func activityColor(for kind: HolidayActivityKind) -> Color {
        switch kind {
        case .flights: .blue
        case .hotels: .purple
        case .carHire: .orange
        case .driving: .brown
        case .transfer: .indigo
        case .boat: .cyan
        case .cycling: .mint
        case .eatingOut: .pink
        case .trips: .green
        case .insurance: .teal
        case .other: .secondary
        }
    }

    @discardableResult
    private func handleDrop(_ items: [String], onto date: Date, atIndex index: Int) -> Bool {
        guard let idString = items.first,
              let id = UUID(uuidString: idString),
              let activity = holiday.activities.first(where: { $0.id == id }) else {
            return false
        }

        let targetDay = calendar.startOfDay(for: date)
        let startDayActivities = HolidayService.activitiesStarting(on: targetDay, holiday: holiday)
        let wasOnTargetDay = HolidayService.resolvedStartDate(activity: activity, holiday: holiday)
            .map { calendar.isDate($0, inSameDayAs: targetDay) } ?? false

        if wasOnTargetDay,
           let currentIndex = startDayActivities.firstIndex(where: { $0.id == id }),
           currentIndex == index {
            return false
        }

        HolidayService.repositionActivityOnCalendarDay(
            activity,
            onDay: targetDay,
            atIndex: index,
            holiday: holiday
        )

        do {
            try modelContext.save()
            if !wasOnTargetDay, holiday.status == .committed {
                let settings = try AppDataService.ensureSettings(in: modelContext)
                let months = try AppDataService.fetchMonths(settings: settings, in: modelContext)
                let allTiles = try AppDataService.fetchAllTiles(in: modelContext)
                try HolidayService.syncCommittedHoliday(
                    holiday: holiday,
                    settings: settings,
                    months: months,
                    allTiles: allTiles,
                    in: modelContext
                )
            }
            return true
        } catch {
            print("Calendar activity move save failed: \(error)")
            return false
        }
    }

    private func openDaySchedule(_ dayStart: Date) {
        selectPasteTarget(dayStart)
        onOpenDaySchedule(dayStart)
    }

    private func selectPasteTarget(_ dayStart: Date) {
        pasteTargetDate = dayStart
        onKeyboardFocus()
    }

    private func selectActivity(_ activity: HolidayActivity, defaultDay: Date?) {
        selectedActivityID = activity.id
        pasteTargetDate = HolidayService.resolvedStartDate(activity: activity, holiday: holiday) ?? defaultDay
        onKeyboardFocus()
    }

    private func copyActivity(_ activity: HolidayActivity) {
        selectActivity(activity, defaultDay: nil)
        copiedActivityID = activity.id
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
            print("Calendar activity paste failed: \(error)")
        }
    }

    private func deleteActivity() {
        guard let activity = activityPendingDeletion else { return }
        do {
            try HolidayService.deleteActivity(activity, from: holiday, allTiles: tiles, in: modelContext)
        } catch {
            print("Calendar activity delete failed: \(error)")
        }
        activityPendingDeletion = nil
    }
}
