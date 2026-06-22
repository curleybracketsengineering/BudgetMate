import CoreLocation
import Foundation
import MapKit
import SwiftData

enum HolidayGeocodingService {
    static func searchQuery(locationName: String, countryName: String) -> String {
        let location = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !location.isEmpty else { return "" }
        if country.isEmpty { return location }
        return "\(location), \(country)"
    }

    static func resolveCoordinates(
        for stops: [HolidayItineraryService.MapStop],
        activities: [HolidayActivity],
        in context: ModelContext?
    ) async -> [HolidayItineraryService.MapStop] {
        var resolvedStops: [HolidayItineraryService.MapStop] = []
        var didUpdateModel = false

        for stop in stops {
            var updatedStop = stop
            let query = searchQuery(locationName: stop.locationName, countryName: stop.countryName)

            if stop.coordinate == nil {
                if let coordinate = await geocode(searchQuery: query) {
                    updatedStop.latitude = coordinate.latitude
                    updatedStop.longitude = coordinate.longitude

                    if let activity = activities.first(where: { $0.id == stop.activityID }) {
                        activity.latitude = coordinate.latitude
                        activity.longitude = coordinate.longitude
                        activity.geocodedSearchQuery = query
                        didUpdateModel = true
                    }
                }
            }

            resolvedStops.append(updatedStop)
        }

        if didUpdateModel, let context {
            try? context.save()
        }

        return resolvedStops
    }

    private static func geocode(searchQuery: String) async -> CLLocationCoordinate2D? {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems.first?.location.coordinate
        } catch {
            return nil
        }
    }
}
