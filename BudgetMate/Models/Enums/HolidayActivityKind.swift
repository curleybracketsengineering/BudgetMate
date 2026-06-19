import Foundation

enum HolidayActivityKind: String, Codable, CaseIterable, Identifiable {
    case flights
    case hotels
    case eatingOut
    case trips
    case carHire
    case insurance
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flights: "Flights"
        case .hotels: "Hotels"
        case .eatingOut: "Eating out"
        case .trips: "Trips & excursions"
        case .carHire: "Car hire"
        case .insurance: "Insurance"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .flights: "airplane"
        case .hotels: "bed.double"
        case .eatingOut: "fork.knife"
        case .trips: "map"
        case .carHire: "car"
        case .insurance: "shield"
        case .other: "ellipsis.circle"
        }
    }
}
