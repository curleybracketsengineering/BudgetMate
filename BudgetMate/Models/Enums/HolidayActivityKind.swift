import Foundation

enum HolidayActivityKind: String, Codable, CaseIterable, Identifiable {
    case flights
    case hotels
    case eatingOut
    case trips
    case carHire
    case driving
    case transfer
    case boat
    case cycling
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
        case .driving: "Driving"
        case .transfer: "Transfer"
        case .boat: "Boat"
        case .cycling: "Cycling"
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
        case .driving: "steeringwheel"
        case .transfer: "bus"
        case .boat: "ferry"
        case .cycling: "bicycle"
        case .insurance: "shield"
        case .other: "ellipsis.circle"
        }
    }

    /// Stops that belong on the route by default (movement legs and overnight stays).
    var showsOnTripMap: Bool {
        switch self {
        case .flights, .hotels, .carHire, .driving, .transfer, .boat, .cycling:
            true
        case .eatingOut, .trips, .insurance, .other:
            false
        }
    }

    /// Transport legs with optional from / to location fields.
    var hasFromToFields: Bool {
        switch self {
        case .flights, .driving, .transfer, .boat, .cycling:
            true
        default:
            false
        }
    }

    var showsDistanceEstimate: Bool {
        self == .driving
    }

    var showsTravelDurationEstimate: Bool {
        switch self {
        case .flights, .driving:
            true
        default:
            false
        }
    }

    var supportsMultiDayDuration: Bool {
        switch self {
        case .hotels, .carHire: true
        default: false
        }
    }

    func durationLabel(count: Int) -> String {
        switch self {
        case .hotels:
            count == 1 ? "1 night" : "\(count) nights"
        case .carHire:
            count == 1 ? "1 day" : "\(count) days"
        default:
            count == 1 ? "1 day" : "\(count) days"
        }
    }

    func tripDayDurationLabel(dayNumber: Int, total: Int) -> String? {
        guard supportsMultiDayDuration,
              dayNumber >= 1, dayNumber <= total else { return nil }

        if dayNumber == 1 {
            return durationLabel(count: total)
        }

        switch self {
        case .hotels:
            return "Night \(dayNumber) of \(total)"
        case .carHire:
            return "Day \(dayNumber) of \(total)"
        default:
            return nil
        }
    }

    var durationStartDateLabel: String {
        switch self {
        case .hotels: "Check in"
        case .carHire: "Pickup"
        default: "Starts"
        }
    }

    var durationEndDateLabel: String {
        switch self {
        case .hotels: "Check out"
        case .carHire: "Drop-off"
        default: "Ends"
        }
    }

    var durationStepperLabel: String {
        switch self {
        case .hotels: "Nights"
        case .carHire: "Days"
        default: "Days"
        }
    }
}
