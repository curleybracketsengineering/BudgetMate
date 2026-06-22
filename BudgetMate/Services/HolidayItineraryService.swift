import CoreLocation
import Foundation

enum HolidayItineraryService {
    enum MapStopRole: String {
        case origin
        case destination
    }

    struct MapStop: Identifiable {
        let id: String
        let order: Int
        let activityID: UUID
        let role: MapStopRole
        let name: String
        let locationName: String
        let countryName: String
        let kind: HolidayActivityKind
        let startDate: Date?
        let endDate: Date?
        let tripDayStart: Int?
        let tripDayEnd: Int?
        var latitude: Double
        var longitude: Double
        /// When true, resolved coordinates are written back to the activity's main geocode cache.
        let persistsGeocodeOnActivity: Bool

        var coordinate: CLLocationCoordinate2D? {
            guard latitude != 0 || longitude != 0 else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        func isActive(onTripDay day: Int) -> Bool {
            guard let tripDayStart, let tripDayEnd else { return false }
            return day >= tripDayStart && day <= tripDayEnd
        }
    }

    static func resolvedDestinationName(activity: HolidayActivity, holiday: Holiday) -> String {
        let stored = activity.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty { return stored }

        let inferred = HolidayLocationParser.inferDestination(from: activity.name, kind: activity.kind)
        if !inferred.isEmpty { return inferred }

        if activity.kind == .hotels || activity.kind == .carHire {
            let holidayDestination = holiday.destination.trimmingCharacters(in: .whitespacesAndNewlines)
            if !holidayDestination.isEmpty { return holidayDestination }
        }

        return ""
    }

    static func resolvedOriginName(activity: HolidayActivity) -> String {
        let stored = activity.fromLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty { return stored }

        return HolidayLocationParser.inferOrigin(from: activity.name, kind: activity.kind)
    }

    static func resolvedCountryName(activity: HolidayActivity, holiday: Holiday) -> String {
        let activityCountry = activity.countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !activityCountry.isEmpty { return activityCountry }

        let holidayCountry = holiday.countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !holidayCountry.isEmpty { return holidayCountry }

        return ""
    }

    static func mapStops(for holiday: Holiday) -> [MapStop] {
        let sorted = HolidayService.chronologicallySortedActivities(for: holiday)
        var stops: [MapStop] = []
        var order = 0
        var previousLocation: String?

        for activity in sorted {
            let destinationName = resolvedDestinationName(activity: activity, holiday: holiday)
            let originName = activity.kind.hasFromToFields
                ? resolvedOriginName(activity: activity)
                : ""
            let hasExplicitLocation = !activity.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !activity.fromLocationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            guard activity.kind.showsOnTripMap || hasExplicitLocation else { continue }
            guard !destinationName.isEmpty || !originName.isEmpty else { continue }

            let countryName = resolvedCountryName(activity: activity, holiday: holiday)
            let startDate = HolidayService.resolvedStartDate(activity: activity, holiday: holiday)
            let endDate = HolidayService.resolvedEndDate(activity: activity, holiday: holiday)
            let dayRange = tripDayRange(
                startDate: startDate,
                endDate: endDate,
                tripStart: holiday.plannedStartDate
            )

            if activity.kind.hasFromToFields,
               !originName.isEmpty,
               previousLocation?.compare(originName, options: .caseInsensitive) != .orderedSame {
                order += 1
                stops.append(
                    makeStop(
                        activity: activity,
                        role: .origin,
                        order: order,
                        locationName: originName,
                        countryName: countryName,
                        startDate: startDate,
                        endDate: endDate,
                        dayRange: dayRange,
                        persistsGeocodeOnActivity: false
                    )
                )
                previousLocation = originName
            }

            if !destinationName.isEmpty,
               previousLocation?.compare(destinationName, options: .caseInsensitive) != .orderedSame {
                order += 1
                stops.append(
                    makeStop(
                        activity: activity,
                        role: .destination,
                        order: order,
                        locationName: destinationName,
                        countryName: countryName,
                        startDate: startDate,
                        endDate: endDate,
                        dayRange: dayRange,
                        persistsGeocodeOnActivity: true
                    )
                )
                previousLocation = destinationName
            }
        }

        return stops
    }

    static func tripDayCount(for holiday: Holiday) -> Int? {
        guard let start = holiday.plannedStartDate else { return nil }
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)

        var latest = holiday.plannedEndDate.map { calendar.startOfDay(for: $0) } ?? startDay
        for activity in holiday.activities {
            if let end = HolidayService.resolvedEndDate(activity: activity, holiday: holiday) {
                latest = max(latest, calendar.startOfDay(for: end))
            } else if let activityStart = HolidayService.resolvedStartDate(activity: activity, holiday: holiday) {
                latest = max(latest, calendar.startOfDay(for: activityStart))
            }
        }

        let delta = calendar.dateComponents([.day], from: startDay, to: latest).day ?? 0
        return max(delta + 1, 1)
    }

    static func tripDay(for date: Date, tripStart: Date) -> Int {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: tripStart)
        let targetDay = calendar.startOfDay(for: date)
        let delta = calendar.dateComponents([.day], from: startDay, to: targetDay).day ?? 0
        return max(delta + 1, 1)
    }

    static func date(forTripDay day: Int, tripStart: Date) -> Date? {
        guard day > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: day - 1, to: Calendar.current.startOfDay(for: tripStart))
    }

    static func hasMappableContent(for holiday: Holiday) -> Bool {
        !mapStops(for: holiday).isEmpty
    }

    private static func makeStop(
        activity: HolidayActivity,
        role: MapStopRole,
        order: Int,
        locationName: String,
        countryName: String,
        startDate: Date?,
        endDate: Date?,
        dayRange: (start: Int, end: Int)?,
        persistsGeocodeOnActivity: Bool
    ) -> MapStop {
        let searchQuery = HolidayGeocodingService.searchQuery(
            locationName: locationName,
            countryName: countryName
        )
        let hasValidCachedCoordinate = persistsGeocodeOnActivity
            && activity.hasStoredCoordinate
            && activity.geocodedSearchQuery == searchQuery

        return MapStop(
            id: "\(activity.id.uuidString)-\(role.rawValue)",
            order: order,
            activityID: activity.id,
            role: role,
            name: activity.name,
            locationName: locationName,
            countryName: countryName,
            kind: activity.kind,
            startDate: startDate,
            endDate: endDate,
            tripDayStart: dayRange?.start,
            tripDayEnd: dayRange?.end,
            latitude: hasValidCachedCoordinate ? activity.latitude : 0,
            longitude: hasValidCachedCoordinate ? activity.longitude : 0,
            persistsGeocodeOnActivity: persistsGeocodeOnActivity
        )
    }

    private static func tripDayRange(
        startDate: Date?,
        endDate: Date?,
        tripStart: Date?
    ) -> (start: Int, end: Int)? {
        guard let tripStart, let startDate else { return nil }
        let startDay = tripDay(for: startDate, tripStart: tripStart)
        if let endDate {
            let endDay = tripDay(for: endDate, tripStart: tripStart)
            return (min(startDay, endDay), max(startDay, endDay))
        }
        return (startDay, startDay)
    }
}
