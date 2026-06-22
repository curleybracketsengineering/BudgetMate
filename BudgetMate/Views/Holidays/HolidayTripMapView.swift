import MapKit
import SwiftData
import SwiftUI

struct HolidayTripMapView: View {
    @Environment(\.modelContext) private var modelContext

    let holiday: Holiday
    @Binding var isInteractingWithMap: Bool
    @Binding var copiedActivityID: UUID?
    @Binding var selectedActivityID: UUID?
    @Binding var pasteTargetDate: Date?
    @Binding var pasteTargetTripDay: Int?
    var onKeyboardFocus: () -> Void = {}

    @State private var stops: [HolidayItineraryService.MapStop] = []
    @State private var selectedTripDay = 1
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var fittedRegion: MKCoordinateRegion?
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var isLoading = false
    @State private var unresolvedCount = 0

    private let mapHeight: CGFloat = 420

    init(
        holiday: Holiday,
        isInteractingWithMap: Binding<Bool> = .constant(false),
        copiedActivityID: Binding<UUID?> = .constant(nil),
        selectedActivityID: Binding<UUID?> = .constant(nil),
        pasteTargetDate: Binding<Date?> = .constant(nil),
        pasteTargetTripDay: Binding<Int?> = .constant(nil),
        onKeyboardFocus: @escaping () -> Void = {}
    ) {
        self.holiday = holiday
        _isInteractingWithMap = isInteractingWithMap
        _copiedActivityID = copiedActivityID
        _selectedActivityID = selectedActivityID
        _pasteTargetDate = pasteTargetDate
        _pasteTargetTripDay = pasteTargetTripDay
        self.onKeyboardFocus = onKeyboardFocus
    }

    private var tripDayCount: Int? {
        HolidayItineraryService.tripDayCount(for: holiday)
    }

    private var mappableCoordinates: [CLLocationCoordinate2D] {
        stops.compactMap(\.coordinate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trip map")
                .font(.headline)

            if isLoading {
                ProgressView("Loading map…")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if stops.isEmpty {
                ContentUnavailableView(
                    "No locations yet",
                    systemImage: "map",
                    description: Text("Add a location to hotel or flight activities to see your route.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                mapContent
                dayScrubber
                stopList
            }
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .task(id: taskKey) {
            await loadMap()
        }
    }

    private var taskKey: String {
        let signature = holiday.activities
            .sorted { $0.sortOrder < $1.sortOrder }
            .map {
                "\($0.id.uuidString)|\($0.locationName)|\($0.countryName)|\($0.name)|\($0.sortOrder)|\($0.plannedStartDate?.timeIntervalSince1970 ?? 0)|\($0.plannedEndDate?.timeIntervalSince1970 ?? 0)|\($0.nights)|\($0.estimateSourceRaw)"
            }
            .joined(separator: ";")
        return "\(holiday.id.uuidString)|\(holiday.countryName)|\(holiday.plannedStartDate?.timeIntervalSince1970 ?? 0)|\(signature)"
    }

    @ViewBuilder
    private var mapContent: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $mapPosition) {
                if mappableCoordinates.count >= 2 {
                    MapPolyline(coordinates: mappableCoordinates)
                        .stroke(Color.accentColor, lineWidth: 3)
                }

                ForEach(stops) { stop in
                    if let coordinate = stop.coordinate {
                        Annotation(stop.locationName, coordinate: coordinate) {
                            stopMarker(for: stop)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            #if os(iOS) || os(visionOS)
            .mapInteractionModes([.pan, .zoom, .rotate])
            #endif
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                visibleRegion = context.region
            }

            mapZoomControls
                .padding(10)
        }
        .frame(maxWidth: .infinity, minHeight: mapHeight, maxHeight: mapHeight)
        .contentShape(Rectangle())
        .clipShape(RoundedRectangle(cornerRadius: 8))
        #if os(macOS)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isInteractingWithMap = true
            case .ended:
                isInteractingWithMap = false
            }
        }
        #endif

        if unresolvedCount > 0 {
            Text("\(unresolvedCount) location\(unresolvedCount == 1 ? "" : "s") could not be placed on the map.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var mapZoomControls: some View {
        VStack(spacing: 6) {
            mapControlButton(systemImage: "plus", accessibilityLabel: "Zoom in") {
                adjustZoom(by: 0.65)
            }
            mapControlButton(systemImage: "minus", accessibilityLabel: "Zoom out") {
                adjustZoom(by: 1.45)
            }
            mapControlButton(systemImage: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "Fit route") {
                fitRoute()
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func mapControlButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var dayScrubber: some View {
        if let tripDayCount, tripDayCount > 1, let tripStart = holiday.plannedStartDate {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Day \(selectedTripDay) of \(tripDayCount)")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if let date = HolidayItineraryService.date(forTripDay: selectedTripDay, tripStart: tripStart) {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Slider(
                    value: Binding(
                        get: { Double(selectedTripDay) },
                        set: { selectedTripDay = Int($0.rounded()) }
                    ),
                    in: 1...Double(tripDayCount),
                    step: 1
                )
            }
        }
    }

    @ViewBuilder
    private var stopList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drag activities between days to fix the itinerary.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HolidayTripDayScheduleView(
                holiday: holiday,
                copiedActivityID: $copiedActivityID,
                selectedActivityID: $selectedActivityID,
                pasteTargetDate: $pasteTargetDate,
                pasteTargetTripDay: $pasteTargetTripDay,
                onKeyboardFocus: onKeyboardFocus,
                includedActivityIDs: Set(stops.map(\.activityID)),
                stopLookup: Dictionary(uniqueKeysWithValues: stops.map { ($0.activityID, $0) }),
                highlightedTripDay: tripDayCount != nil ? selectedTripDay : nil
            )
        }
    }

    @ViewBuilder
    private func stopMarker(for stop: HolidayItineraryService.MapStop) -> some View {
        ZStack {
            Circle()
                .fill(circleColor(for: stop))
                .frame(width: 28, height: 28)
            Text("\(stop.order)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
        .shadow(radius: 2)
    }

    private func circleColor(for stop: HolidayItineraryService.MapStop) -> Color {
        if tripDayCount != nil, stop.isActive(onTripDay: selectedTripDay) {
            return .accentColor
        }
        if tripDayCount != nil {
            return .gray.opacity(0.55)
        }
        return .accentColor
    }

    @MainActor
    private func loadMap() async {
        isLoading = true
        defer { isLoading = false }

        let baseStops = HolidayItineraryService.mapStops(for: holiday)
        stops = await HolidayGeocodingService.resolveCoordinates(
            for: baseStops,
            activities: holiday.activities,
            in: modelContext
        )
        unresolvedCount = stops.filter { $0.coordinate == nil }.count

        if let tripDayCount, selectedTripDay > tripDayCount {
            selectedTripDay = 1
        }

        updateCamera()
    }

    @MainActor
    private func updateCamera() {
        let coordinates = mappableCoordinates
        guard !coordinates.isEmpty else {
            mapPosition = .automatic
            fittedRegion = nil
            visibleRegion = nil
            return
        }

        let region: MKCoordinateRegion
        if coordinates.count == 1, let coordinate = coordinates.first {
            region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 2.5, longitudeDelta: 2.5)
            )
        } else {
            var minLat = coordinates[0].latitude
            var maxLat = coordinates[0].latitude
            var minLon = coordinates[0].longitude
            var maxLon = coordinates[0].longitude

            for coordinate in coordinates {
                minLat = min(minLat, coordinate.latitude)
                maxLat = max(maxLat, coordinate.latitude)
                minLon = min(minLon, coordinate.longitude)
                maxLon = max(maxLon, coordinate.longitude)
            }

            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(
                    latitudeDelta: max((maxLat - minLat) * 1.45, 1.5),
                    longitudeDelta: max((maxLon - minLon) * 1.45, 1.5)
                )
            )
        }

        fittedRegion = region
        visibleRegion = region
        mapPosition = .region(region)
    }

    @MainActor
    private func adjustZoom(by factor: Double) {
        guard var region = visibleRegion ?? fittedRegion else { return }
        region.span.latitudeDelta = clampSpan(region.span.latitudeDelta * factor)
        region.span.longitudeDelta = clampSpan(region.span.longitudeDelta * factor)
        visibleRegion = region
        mapPosition = .region(region)
    }

    @MainActor
    private func fitRoute() {
        guard let fittedRegion else { return }
        visibleRegion = fittedRegion
        mapPosition = .region(fittedRegion)
    }

    private func clampSpan(_ span: Double) -> Double {
        min(max(span, 0.02), 120)
    }
}
