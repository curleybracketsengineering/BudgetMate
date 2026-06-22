import Foundation

enum HolidayLocationParser {
    static func infer(from name: String, kind: HolidayActivityKind) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if kind == .flights, let destination = flightDestination(from: trimmed) {
            return destination
        }

        var candidate = trimmed

        if let range = candidate.range(of: #"\s+\d+\s+nights?\b"#, options: [.regularExpression, .caseInsensitive]) {
            candidate = String(candidate[..<range.lowerBound])
        }

        if let separator = candidate.firstIndex(where: { ["—", "–", "-"].contains(String($0)) }) {
            candidate = String(candidate[..<separator])
        }

        if let slash = candidate.firstIndex(of: "/") {
            candidate = String(candidate[..<slash])
        }

        candidate = candidate
            .replacingOccurrences(of: #"\b(open-jaw|business|economy|return|flights?|hotel|hotels?)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return candidate
    }

    private static func flightDestination(from name: String) -> String? {
        let lowercased = name.lowercased()
        guard let toRange = lowercased.range(of: " to ") else { return nil }

        var destination = String(name[toRange.upperBound...])
            .replacingOccurrences(of: #"\b(open-jaw|business|economy|return|flights?)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let slash = destination.firstIndex(of: "/") {
            destination = String(destination[..<slash]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return destination.isEmpty ? nil : destination
    }
}
