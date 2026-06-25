import Foundation
import SwiftData

@Model
final class HolidayActivity {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = HolidayActivityKind.other.rawValue
    var amountMinorUnits: Int = 0
    /// 0 means inherit from holiday default or trip start month.
    var plannedYear: Int = 0
    var plannedMonth: Int = 0
    var plannedStartDate: Date?
    var plannedEndDate: Date?
    /// Departure city or place for transport legs. Empty means no map stop.
    var fromLocationName: String = ""
    /// Arrival city, town, or airport shown on the trip map. Empty means no map stop.
    var locationName: String = ""
    /// Country used to disambiguate map geocoding. Empty inherits the trip default.
    var countryName: String = ""
    /// Cached geocode. Both 0 means not yet resolved.
    var latitude: Double = 0
    var longitude: Double = 0
    /// Search query used for the cached coordinate. Cleared when location or country changes.
    var geocodedSearchQuery: String = ""
    /// Estimated route distance in kilometres. 0 means unset.
    var estimatedDistanceKm: Double = 0
    /// Estimated travel time in minutes (drive or flight). 0 means unset.
    var estimatedDurationMinutes: Int = 0
    /// When true, from/to changes do not overwrite distance or duration.
    var travelEstimatesAreManual: Bool = false
    /// Nights at this stop. 0 means same-day or unknown (e.g. a flight leg).
    var nights: Int = 0
    var linkedAccountId: UUID?
    var subCategoryId: UUID?
    var sortOrder: Int = 0
    var notes: String = ""
    var estimateSourceRaw: String = HolidayActivityEstimateSource.manual.rawValue
    var estimateNote: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deviceId: String = ""

    var holiday: Holiday?

    init(name: String = "", kind: HolidayActivityKind = .other) {
        self.name = name
        self.kindRaw = kind.rawValue
    }

    var kind: HolidayActivityKind {
        get { HolidayActivityKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var estimateSource: HolidayActivityEstimateSource {
        get { HolidayActivityEstimateSource(rawValue: estimateSourceRaw) ?? .manual }
        set { estimateSourceRaw = newValue.rawValue }
    }

    var hasStoredCoordinate: Bool {
        latitude != 0 || longitude != 0
    }

    func clearGeocodeCache() {
        latitude = 0
        longitude = 0
        geocodedSearchQuery = ""
    }

    var coordinate: (latitude: Double, longitude: Double)? {
        guard hasStoredCoordinate else { return nil }
        return (latitude, longitude)
    }
}
