import SwiftUI
import SwiftData

struct HolidaysView: View {
    @Binding var selectedHoliday: Holiday?

    var body: some View {
        HolidaysListView(selectedHoliday: $selectedHoliday)
            .navigationTitle("Holidays & Events")
    }
}

struct HolidaysListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Holiday.displayOrder), SortDescriptor(\Holiday.name)]) private var holidays: [Holiday]
    @Query private var settingsList: [AppSettings]

    @Binding var selectedHoliday: Holiday?
    @State private var showingNewHoliday = false
    @State private var holidayPendingDeletion: Holiday?

    private var currency: AppCurrency { settingsList.first?.currency ?? .GBP }

    private var draftHolidays: [Holiday] {
        holidays.filter { $0.status == .draft }
    }

    private var committedHolidays: [Holiday] {
        holidays.filter { $0.status == .committed }
    }

    var body: some View {
        List(selection: $selectedHoliday) {
            if holidays.isEmpty {
                ContentUnavailableView(
                    "No holidays yet",
                    systemImage: "airplane",
                    description: Text("Create a trip, add activities, then push costs into your monthly plan.")
                )
            } else {
                if !draftHolidays.isEmpty {
                    Section("Draft") {
                        ForEach(draftHolidays) { holiday in
                            holidayRow(holiday)
                                .tag(holiday)
                        }
                    }
                }

                if !committedHolidays.isEmpty {
                    Section("In monthly plan") {
                        ForEach(committedHolidays) { holiday in
                            holidayRow(holiday)
                                .tag(holiday)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewHoliday = true
                } label: {
                    Label("New holiday", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewHoliday) {
            HolidayFormView(currency: currency) { created in
                selectedHoliday = created
            }
        }
        .confirmationDialog(
            "Delete holiday?",
            isPresented: Binding(
                get: { holidayPendingDeletion != nil },
                set: { if !$0 { holidayPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteHoliday()
            }
        } message: {
            if let holiday = holidayPendingDeletion {
                Text("“\(holiday.name)” and its activities will be removed. Any linked monthly tiles will also be deleted.")
            }
        }
    }

    @ViewBuilder
    private func holidayRow(_ holiday: Holiday) -> some View {
        let summary = HolidayService.summary(for: holiday)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(holiday.name.isEmpty ? "Untitled trip" : holiday.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if let dates = holiday.dateRangeLabel {
                        Text(dates)
                    }
                    if !holiday.destination.isEmpty {
                        if holiday.dateRangeLabel != nil { Text("·") }
                        Text(holiday.destination)
                    }
                    if summary.totalMinorUnits > 0 || !holiday.activities.isEmpty {
                        Text("·")
                        Text("\(holiday.activities.count) activities")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if summary.totalMinorUnits > 0 {
                Text(MoneyFormatter.format(minorUnits: summary.totalMinorUnits, currency: currency))
                    .font(.body.monospacedDigit())
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                holidayPendingDeletion = holiday
            }
        }
    }

    private func deleteHoliday() {
        guard let holiday = holidayPendingDeletion else { return }
        do {
            let tiles = try AppDataService.fetchAllTiles(in: modelContext)
            try HolidayService.deleteHoliday(holiday, allTiles: tiles, in: modelContext)
            if selectedHoliday?.id == holiday.id {
                selectedHoliday = nil
            }
        } catch {
            print("Delete holiday failed: \(error)")
        }
        holidayPendingDeletion = nil
    }
}
