import CoreLocation
import Foundation

enum HolidayItineraryService {
    struct MapStop: Identifiable {
        let id: UUID
        let order: Int
        let activityID: UUID
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

        var coordinate: CLLocationCoordinate2D? {
            guard latitude != 0 || longitude != 0 else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        func isActive(onTripDay day: Int) -> Bool {
            guard let tripDayStart, let tripDayEnd else { return false }
            return day >= tripDayStart && day <= tripDayEnd
        }
    }

    static func resolvedLocationName(activity: HolidayActivity, holiday: Holiday) -> String {
        let stored = activity.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty { return stored }

        let inferred = HolidayLocationParser.infer(from: activity.name, kind: activity.kind)
        if !inferred.isEmpty { return inferred }

        if activity.kind == .flights, !holiday.origin.isEmpty {
            return holiday.origin
        }
        if !holiday.destination.isEmpty {
            return holiday.destination
        }
        return ""
    }

    static func resolvedCountryName(activity: HolidayActivity, holiday: Holiday) -> String {
        let activityCountry = activity.countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !activityCountry.isEmpty { return activityCountry }

        let holidayCountry = holiday.countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !holidayCountry.isEmpty { return holidayCountry }

        return holiday.destination.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func mapStops(for holiday: Holiday) -> [MapStop] {
        let sorted = HolidayService.chronologicallySortedActivities(for: holiday)
        var stops: [MapStop] = []
        var order = 0
        var previousLocation: String?

        for activity in sorted {
            let locationName = resolvedLocationName(activity: activity, holiday: holiday)
            guard !locationName.isEmpty else { continue }
            guard activity.kind.showsOnTripMap || !activity.locationName.isEmpty else { continue }

            if let previousLocation,
               previousLocation.compare(locationName, options: .caseInsensitive) == .orderedSame {
                continue
            }

            order += 1
            let countryName = resolvedCountryName(activity: activity, holiday: holiday)
            let searchQuery = HolidayGeocodingService.searchQuery(
                locationName: locationName,
                countryName: countryName
            )
            let hasValidCachedCoordinate = activity.hasStoredCoordinate
                && activity.geocodedSearchQuery == searchQuery
            let startDate = HolidayService.resolvedStartDate(activity: activity, holiday: holiday)
            let endDate = HolidayService.resolvedEndDate(activity: activity, holiday: holiday)
            let dayRange = tripDayRange(
                startDate: startDate,
                endDate: endDate,
                tripStart: holiday.plannedStartDate
            )

            stops.append(
                MapStop(
                    id: activity.id,
                    order: order,
                    activityID: activity.id,
                    name: activity.name,
                    locationName: locationName,
                    countryName: countryName,
                    kind: activity.kind,
                    startDate: startDate,
                    endDate: endDate,
                    tripDayStart: dayRange?.start,
                    tripDayEnd: dayRange?.end,
                    latitude: hasValidCachedCoordinate ? activity.latitude : 0,
                    longitude: hasValidCachedCoordinate ? activity.longitude : 0
                )
            )
            previousLocation = locationName
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
