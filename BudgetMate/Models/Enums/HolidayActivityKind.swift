import Foundation

enum HolidayActivityKind: String, Codable, CaseIterable, Identifiable {
    case flights
    case hotels
    case eatingOut
    case trips
    case carHire
    case transfer
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
        case .transfer: "Transfer"
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
        case .transfer: "bus"
        case .insurance: "shield"
        case .other: "ellipsis.circle"
        }
    }

    var showsOnTripMap: Bool {
        switch self {
        case .flights, .hotels, .trips, .carHire, .transfer, .eatingOut:
            true
        case .insurance, .other:
            false
        }
    }
}
