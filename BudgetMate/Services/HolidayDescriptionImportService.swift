import Foundation
import FoundationModels

enum HolidayDescriptionImportError: LocalizedError {
    case modelUnavailable(String)
    case emptyInput
    case noItemsExtracted
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let message):
            message
        case .emptyInput:
            "Paste a trip description before analyzing."
        case .noItemsExtracted:
            "No activities could be extracted. Try a shorter section focused on the route and budget."
        case .generationFailed(let message):
            message
        }
    }
}

enum HolidayDescriptionImportService {
    static let extractionInstructions = """
        You extract structured holiday planning items from travel write-ups for a budget app.

        Rules:
        - Create one item per bookable stop or travel leg (per-stop/leg granularity).
        - Flights: one row for long-haul open-jaw or return tickets when bundled; separate rows for clear internal legs (e.g. Johannesburg to Gqeberha).
        - Hotels: one row per stay location (e.g. Doha outbound, Johannesburg, Shamwari, Cape Town).
        - Car hire: one row per rental; set nights to the hire duration in days (e.g. 10 for a 10-day hire).
        - Put lodge or hotel shortlists, activity ideas, and markdown links in notes — not as separate rows.
        - Transfers: one row per airport shuttle, hotel transfer, or private transfer leg.
        - Driving: one row per self-drive leg (fuel, tolls, parking) — not car hire.
        - Boat: one row per ferry, cruise segment, or water crossing.
        - Cycling: one row per cycling leg.
        - Use kind exactly as one of: flights, hotels, eatingOut, trips, carHire, driving, transfer, boat, cycling, insurance, other.
        - Only set amountLowGBP and amountHighGBP when the source text states figures for that item.
        - Use 0 for amountLowGBP, amountHighGBP, nights, or durationNights when unknown.
        - Set location to the arrival city, town, or airport for map display (e.g. Cape Town, Doha, Shamwari).
        - For transport legs (flights, transfer, driving, boat, cycling), location is where the leg ends.
        - For flights and other transport, include departure in the name as "Origin to Destination" when known.
        - Use empty strings for unknown text fields.
        - Prefer fewer well-described items over many thin rows (aim for roughly 12–20 items).
        - Preserve useful markdown links in notes.
        """

    static func availabilityMessage() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device is not eligible for Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to import trip descriptions."
        case .unavailable(.modelNotReady):
            return "The on-device language model is still downloading. Try again shortly."
        case .unavailable:
            return "Apple Intelligence is not available on this device."
        @unknown default:
            return "Apple Intelligence is not available."
        }
    }

    static func isAvailable() -> Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    static func extract(from rawDescription: String, currency: AppCurrency) async throws -> (metadata: HolidayTripMetadataDraft, items: [HolidayActivityImportDraft]) {
        let trimmed = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HolidayDescriptionImportError.emptyInput }

        if let message = availabilityMessage() {
            throw HolidayDescriptionImportError.modelUnavailable(message)
        }

        let prepared = HolidayDescriptionPreprocessor.preprocess(trimmed)
        let session = LanguageModelSession(instructions: extractionInstructions)

        let prompt = """
            Extract holiday planning items from this trip description.
            Currency for amounts is \(currency.rawValue). Interpret £ or GBP values as amountLowGBP and amountHighGBP.

            ---
            \(prepared)
            ---
            """

        do {
            let response = try await session.respond(to: prompt, generating: ExtractedHolidayPlan.self)
            let plan = response.content
            let drafts = plan.items
                .map { HolidayActivityImportDraft.from(extracted: $0, currency: currency) }
                .filter { !$0.name.isEmpty }

            guard !drafts.isEmpty else {
                throw HolidayDescriptionImportError.noItemsExtracted
            }

            var metadata = HolidayTripMetadataDraft()
            let tripName = plan.tripName.trimmingCharacters(in: .whitespacesAndNewlines)
            let origin = plan.origin.trimmingCharacters(in: .whitespacesAndNewlines)
            let destination = plan.destination.trimmingCharacters(in: .whitespacesAndNewlines)

            if !tripName.isEmpty {
                metadata.name = tripName
                metadata.applyName = true
            }
            if !origin.isEmpty {
                metadata.origin = origin
                metadata.applyOrigin = true
            }
            if !destination.isEmpty {
                metadata.destination = destination
                metadata.applyDestination = true
            }
            if plan.durationNights > 0 {
                metadata.durationNights = plan.durationNights
                metadata.applyDuration = true
            }

            return (metadata, drafts)
        } catch let error as HolidayDescriptionImportError {
            throw error
        } catch {
            throw HolidayDescriptionImportError.generationFailed(error.localizedDescription)
        }
    }
}
