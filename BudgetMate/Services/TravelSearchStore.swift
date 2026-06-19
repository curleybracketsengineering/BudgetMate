import Foundation
import Observation

@Observable
final class TravelSearchStore {
    private enum Keys {
        static let flightProvider = "travel.flightProvider"
        static let hotelProvider = "travel.hotelProvider"
        static let carHireProvider = "travel.carHireProvider"
    }

    var flightSearchProvider: TravelSearchProvider {
        didSet { UserDefaults.standard.set(flightSearchProvider.rawValue, forKey: Keys.flightProvider) }
    }

    var hotelSearchProvider: TravelSearchProvider {
        didSet { UserDefaults.standard.set(hotelSearchProvider.rawValue, forKey: Keys.hotelProvider) }
    }

    var carHireSearchProvider: TravelSearchProvider {
        didSet { UserDefaults.standard.set(carHireSearchProvider.rawValue, forKey: Keys.carHireProvider) }
    }

    init() {
        flightSearchProvider = TravelSearchProvider(rawValue: UserDefaults.standard.string(forKey: Keys.flightProvider) ?? "") ?? .googleFlights
        hotelSearchProvider = TravelSearchProvider(rawValue: UserDefaults.standard.string(forKey: Keys.hotelProvider) ?? "") ?? .googleHotels
        carHireSearchProvider = TravelSearchProvider(rawValue: UserDefaults.standard.string(forKey: Keys.carHireProvider) ?? "") ?? .kayakCars
    }
}
