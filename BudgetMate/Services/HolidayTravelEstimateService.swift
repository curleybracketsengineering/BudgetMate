import CoreLocation
import Foundation
import MapKit

enum HolidayTravelEstimateService {
    struct Estimate {
        var distanceKm: Double?
        var durationMinutes: Int?
    }

    static func estimate(
        kind: HolidayActivityKind,
        fromLocationName: String,
        toLocationName: String,
        countryName: String
    ) async -> Estimate? {
        let from = fromLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else { return nil }

        async let fromCoordinate = HolidayGeocodingService.coordinate(
            locationName: from,
            countryName: countryName
        )
        async let toCoordinate = HolidayGeocodingService.coordinate(
            locationName: to,
            countryName: countryName
        )

        guard let origin = await fromCoordinate,
              let destination = await toCoordinate else {
            return nil
        }

        switch kind {
        case .driving:
            if let driving = await drivingEstimate(from: origin, to: destination) {
                return driving
            }
            return straightLineEstimate(from: origin, to: destination, kind: kind)
        case .flights:
            return flightEstimate(from: origin, to: destination)
        default:
            return nil
        }
    }

    static func inferDurationMinutes(from name: String) -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pattern = #"(?i)(\d+(?:\.\d+)?)\s*(?:hrs?|hours?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let hoursRange = Range(match.range(at: 1), in: trimmed),
              let hours = Double(trimmed[hoursRange]) else {
            return nil
        }

        return max(Int((hours * 60).rounded()), 1)
    }

    static func formatDistanceMiles(km: Double) -> String {
        guard km > 0 else { return "" }
        let miles = km / 1.609_344
        if miles < 10 {
            return String(format: "%.1f", miles)
        }
        return String(Int(miles.rounded()))
    }

    static func parseDistanceMiles(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard let miles = Double(trimmed), miles > 0 else { return nil }
        return miles * 1.609_344
    }

    static func routeSummaryLabel(activity: HolidayActivity, holiday: Holiday) -> String? {
        guard activity.kind.hasFromToFields else { return nil }

        let from = HolidayItineraryService.explicitOriginName(activity: activity)
        let to = HolidayItineraryService.explicitDestinationName(activity: activity)
        var parts: [String] = []

        if !from.isEmpty, !to.isEmpty {
            parts.append("\(from) → \(to)")
        } else if !to.isEmpty {
            parts.append(to)
        } else if !from.isEmpty {
            parts.append(from)
        }

        if activity.kind.showsDistanceEstimate, activity.estimatedDistanceKm > 0 {
            let miles = formatDistanceMiles(km: activity.estimatedDistanceKm)
            if !miles.isEmpty {
                parts.append("\(miles) mi")
            }
        }

        if activity.kind.showsTravelDurationEstimate, activity.estimatedDurationMinutes > 0 {
            parts.append(formatDuration(minutes: activity.estimatedDurationMinutes))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func formatDuration(minutes: Int) -> String {
        guard minutes > 0 else { return "" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0, remainder > 0 {
            return "\(hours)h \(remainder)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(remainder)m"
    }

    static func parseDuration(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if let decimalHours = Double(trimmed.replacingOccurrences(of: "h", with: "")),
           trimmed.contains("h"),
           !trimmed.contains("m") {
            return max(Int((decimalHours * 60).rounded()), 1)
        }

        let hourPattern = #"(?i)(\d+)\s*h"#
        let minutePattern = #"(?i)(\d+)\s*m"#
        var total = 0

        if let regex = try? NSRegularExpression(pattern: hourPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range(at: 1), in: trimmed),
           let hours = Int(trimmed[range]) {
            total += hours * 60
        }

        if let regex = try? NSRegularExpression(pattern: minutePattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range(at: 1), in: trimmed),
           let minutes = Int(trimmed[range]) {
            total += minutes
        }

        if total > 0 {
            return total
        }

        if let minutes = Int(trimmed) {
            return max(minutes, 1)
        }

        return nil
    }

    private static func drivingEstimate(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async -> Estimate? {
        let request = MKDirections.Request()
        request.source = mapItem(at: from)
        request.destination = mapItem(at: to)
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard let route = response.routes.first else { return nil }
            return Estimate(
                distanceKm: route.distance / 1_000,
                durationMinutes: max(Int((route.expectedTravelTime / 60).rounded()), 1)
            )
        } catch {
            return nil
        }
    }

    private static func flightEstimate(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Estimate {
        let distanceKm = haversineDistanceKm(from: from, to: to)
        let groundMinutes = distanceKm < 500 ? 75 : 105
        let cruiseSpeedKmh: Double
        if distanceKm < 400 {
            cruiseSpeedKmh = 420
        } else if distanceKm < 1_500 {
            cruiseSpeedKmh = 680
        } else {
            cruiseSpeedKmh = 840
        }

        let airborneMinutes = Int((distanceKm / cruiseSpeedKmh * 60).rounded())
        return Estimate(
            distanceKm: distanceKm,
            durationMinutes: max(groundMinutes + airborneMinutes, 30)
        )
    }

    private static func straightLineEstimate(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        kind: HolidayActivityKind
    ) -> Estimate {
        let distanceKm = haversineDistanceKm(from: from, to: to)
        let averageSpeedKmh = kind == .driving ? 65.0 : 50.0
        let durationMinutes = max(Int((distanceKm / averageSpeedKmh * 60).rounded()), 1)
        return Estimate(distanceKm: distanceKm, durationMinutes: durationMinutes)
    }

    private static func mapItem(at coordinate: CLLocationCoordinate2D) -> MKMapItem {
        MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
    }

    private static func haversineDistanceKm(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        let origin = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let destination = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return origin.distance(from: destination) / 1_000
    }
}
