import Foundation
import FoundationModels

@Generable
struct ExtractedHolidayPlan {
    @Guide(description: "Trip title if clearly stated in the text.")
    var tripName: String

    @Guide(description: "Origin city or airport if stated, otherwise empty.")
    var origin: String

    @Guide(description: "Primary destination region or country, otherwise empty.")
    var destination: String

    @Guide(description: "Total nights away if stated, otherwise 0.")
    var durationNights: Int

    @Guide(.count(1...25))
    var items: [ExtractedHolidayItem]
}

@Generable
struct ExtractedHolidayItem {
    @Guide(description: "Short label, e.g. Shamwari — 3 nights or Qatar open-jaw business flights.")
    var name: String

    @Guide(description: "Exactly one of: flights, hotels, eatingOut, trips, carHire, driving, transfer, boat, cycling, insurance, other.")
    var kind: String

    @Guide(description: "Nights at this stop or days of car hire if applicable, otherwise 0.")
    var nights: Int

    @Guide(description: "Primary map location: city, town, or airport for this stop or leg. Empty if unknown.")
    var location: String

    @Guide(description: "Lower budget bound in GBP if stated, otherwise 0.")
    var amountLowGBP: Double

    @Guide(description: "Upper budget bound in GBP if stated, otherwise 0.")
    var amountHighGBP: Double

    @Guide(description: "Relevant notes: lodge options, activities, and markdown links for follow-up.")
    var notes: String

    @Guide(description: "Where the amount came from, e.g. budget table, otherwise empty.")
    var estimateSource: String
}

struct HolidayTripMetadataDraft {
    var applyName: Bool = false
    var applyOrigin: Bool = false
    var applyDestination: Bool = false
    var applyDuration: Bool = false
    var name: String = ""
    var origin: String = ""
    var destination: String = ""
    var durationNights: Int = 0
}

struct HolidayActivityImportDraft: Identifiable {
    let id = UUID()
    var isIncluded: Bool = true
    var name: String
    var kind: HolidayActivityKind
    var amountText: String
    var notes: String
    var estimateNote: String
    var nights: Int = 0
    var locationName: String = ""
    var fromLocationName: String = ""

    static func from(extracted: ExtractedHolidayItem, currency: AppCurrency) -> HolidayActivityImportDraft {
        let kind = HolidayActivityKind(rawValue: extracted.kind) ?? .other
        let low = extracted.amountLowGBP
        let high = extracted.amountHighGBP
        let amountText: String
        let estimateNote: String

        if low > 0, high > 0, high >= low {
            let midpoint = (low + high) / 2.0
            let minor = Int((midpoint * Double(currency.minorUnitDivisor)).rounded())
            amountText = MoneyFormatter.majorUnitsString(minorUnits: minor, currency: currency)
            estimateNote = formattedRange(low: low, high: high, currency: currency, source: extracted.estimateSource)
        } else if high > 0 {
            let minor = Int((high * Double(currency.minorUnitDivisor)).rounded())
            amountText = MoneyFormatter.majorUnitsString(minorUnits: minor, currency: currency)
            estimateNote = extracted.estimateSource.nilIfEmpty ?? ""
        } else if low > 0 {
            let minor = Int((low * Double(currency.minorUnitDivisor)).rounded())
            amountText = MoneyFormatter.majorUnitsString(minorUnits: minor, currency: currency)
            estimateNote = extracted.estimateSource.nilIfEmpty ?? ""
        } else {
            amountText = ""
            estimateNote = extracted.estimateSource.nilIfEmpty ?? ""
        }

        let name = extracted.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let extractedLocation = extracted.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationName = extractedLocation.isEmpty
            ? HolidayLocationParser.inferDestination(from: name, kind: kind)
            : extractedLocation
        let fromLocationName = kind.hasFromToFields
            ? HolidayLocationParser.inferOrigin(from: name, kind: kind)
            : ""

        return HolidayActivityImportDraft(
            name: name,
            kind: kind,
            amountText: amountText,
            notes: extracted.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            estimateNote: estimateNote,
            nights: extracted.nights,
            locationName: locationName,
            fromLocationName: fromLocationName
        )
    }

    private static func formattedRange(
        low: Double,
        high: Double,
        currency: AppCurrency,
        source: String
    ) -> String {
        let lowMinor = Int((low * Double(currency.minorUnitDivisor)).rounded())
        let highMinor = Int((high * Double(currency.minorUnitDivisor)).rounded())
        let range = "\(MoneyFormatter.format(minorUnits: lowMinor, currency: currency))–\(MoneyFormatter.format(minorUnits: highMinor, currency: currency))"
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSource.isEmpty { return range }
        return "\(range) (\(trimmedSource))"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
