import Foundation

enum TravelDeepLinkService {
    static func flightSearchURL(
        provider: TravelSearchProvider,
        origin: String,
        destination: String,
        startDate: Date?,
        endDate: Date?
    ) -> URL? {
        let originTrimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationTrimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destinationTrimmed.isEmpty else { return nil }

        switch provider {
        case .skyscanner:
            return skyscannerFlightsURL(
                origin: originTrimmed,
                destination: destinationTrimmed,
                startDate: startDate,
                endDate: endDate
            )
        case .googleFlights:
            return googleFlightsURL(
                origin: originTrimmed,
                destination: destinationTrimmed,
                startDate: startDate,
                endDate: endDate
            )
        case .googleHotels, .kayakCars:
            return nil
        }
    }

    static func hotelSearchURL(
        provider: TravelSearchProvider,
        destination: String,
        startDate: Date?,
        endDate: Date?
    ) -> URL? {
        let destinationTrimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destinationTrimmed.isEmpty else { return nil }

        switch provider {
        case .googleHotels:
            return googleHotelsURL(destination: destinationTrimmed, startDate: startDate, endDate: endDate)
        case .skyscanner, .googleFlights, .kayakCars:
            return googleHotelsURL(destination: destinationTrimmed, startDate: startDate, endDate: endDate)
        }
    }

    static func googleDrivingDirectionsURL(
        origin: String,
        destination: String,
        countryName: String = ""
    ) -> URL? {
        let originTrimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationTrimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originTrimmed.isEmpty, !destinationTrimmed.isEmpty else { return nil }

        let country = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let originQuery = qualifiedPlaceName(originTrimmed, countryName: country)
        let destinationQuery = qualifiedPlaceName(destinationTrimmed, countryName: country)

        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: originQuery),
            URLQueryItem(name: "destination", value: destinationQuery),
            URLQueryItem(name: "travelmode", value: "driving"),
        ]
        return components?.url
    }

    static func carHireSearchURL(
        provider: TravelSearchProvider,
        destination: String,
        startDate: Date?,
        endDate: Date?
    ) -> URL? {
        let destinationTrimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destinationTrimmed.isEmpty else { return nil }

        switch provider {
        case .kayakCars:
            return kayakCarsURL(destination: destinationTrimmed, startDate: startDate, endDate: endDate)
        case .skyscanner, .googleFlights, .googleHotels:
            return kayakCarsURL(destination: destinationTrimmed, startDate: startDate, endDate: endDate)
        }
    }

    private static func skyscannerFlightsURL(
        origin: String,
        destination: String,
        startDate: Date?,
        endDate: Date?
    ) -> URL? {
        let originSlug = slugify(origin.isEmpty ? "anywhere" : origin)
        let destinationSlug = slugify(destination)
        let outbound = skyscannerDate(startDate) ?? "anytime"
        let inbound = skyscannerDate(endDate) ?? "anytime"
        return URL(string: "https://www.skyscanner.net/transport/flights/\(originSlug)/\(destinationSlug)/\(outbound)/\(inbound)/")
    }

    private static func googleFlightsURL(
        origin: String,
        destination: String,
        startDate: Date?,
        endDate: Date?
    ) -> URL? {
        var query = "Flights to \(destination)"
        if !origin.isEmpty { query = "Flights from \(origin) to \(destination)" }
        if let startDate {
            query += " on \(isoDate(startDate))"
        }
        if let endDate {
            query += " returning \(isoDate(endDate))"
        }
        var components = URLComponents(string: "https://www.google.com/travel/flights")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    private static func googleHotelsURL(
        destination: String,
        startDate: Date?,
        endDate: Date?
    ) -> URL? {
        var query = "Hotels in \(destination)"
        if let startDate, let endDate {
            query += " \(isoDate(startDate)) to \(isoDate(endDate))"
        }
        var components = URLComponents(string: "https://www.google.com/travel/hotels")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    private static func kayakCarsURL(
        destination: String,
        startDate: Date?,
        endDate: Date?
    ) -> URL? {
        let slug = slugify(destination)
        let pickup = isoDate(startDate) ?? ""
        let dropoff = isoDate(endDate) ?? pickup
        if pickup.isEmpty {
            return URL(string: "https://www.kayak.co.uk/cars/\(slug)")
        }
        return URL(string: "https://www.kayak.co.uk/cars/\(slug)/\(pickup)/\(dropoff)")
    }

    private static func qualifiedPlaceName(_ place: String, countryName: String) -> String {
        guard !countryName.isEmpty else { return place }
        return "\(place), \(countryName)"
    }

    private static func slugify(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text.lowercased()
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func isoDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return isoDate(date)
    }

    private static func skyscannerDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.dateFormat = "yyMMdd"
        return formatter.string(from: date)
    }
}
