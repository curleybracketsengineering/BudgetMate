import Foundation

enum TravelSearchProvider: String, Codable, CaseIterable, Identifiable {
    case skyscanner
    case googleFlights
    case googleHotels
    case kayakCars

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .skyscanner: "Skyscanner"
        case .googleFlights: "Google Flights"
        case .googleHotels: "Google Hotels"
        case .kayakCars: "Kayak"
        }
    }
}
