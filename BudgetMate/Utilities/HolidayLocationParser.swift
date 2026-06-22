import Foundation

enum HolidayLocationParser {
    struct RouteEndpoints {
        var origin: String
        var destination: String
    }

    static func inferDestination(from name: String, kind: HolidayActivityKind) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if kind.hasFromToFields, let route = routeEndpoints(from: trimmed) {
            return route.destination
        }

        return inferPlaceName(from: trimmed)
    }

    static func inferOrigin(from name: String, kind: HolidayActivityKind) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if kind.hasFromToFields, let route = routeEndpoints(from: trimmed) {
            return route.origin
        }

        return ""
    }

    /// Legacy helper used by import — returns the destination side of a leg when possible.
    static func infer(from name: String, kind: HolidayActivityKind) -> String {
        inferDestination(from: name, kind: kind)
    }

    static func routeEndpoints(from name: String) -> RouteEndpoints? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let patterns = [
            #"(?i)\s+to\s+"#,
            #"\s*->\s*"#,
            #"\s*→\s*"#,
            #"\s*–\s*"#,
            #"\s*—\s*"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: range),
                  let matchRange = Range(match.range, in: trimmed) else { continue }

            var origin = String(trimmed[..<matchRange.lowerBound])
            var destination = String(trimmed[matchRange.upperBound...])
            origin = cleanEndpoint(origin)
            destination = cleanEndpoint(destination)
            guard !origin.isEmpty, !destination.isEmpty else { continue }
            return RouteEndpoints(origin: origin, destination: destination)
        }

        return nil
    }

    private static func inferPlaceName(from name: String) -> String {
        var candidate = name

        if let range = candidate.range(of: #"\s+\d+\s+(nights?|days?|hrs?|hours?)\b"#, options: [.regularExpression, .caseInsensitive]) {
            candidate = String(candidate[..<range.lowerBound])
        }

        if let slash = candidate.firstIndex(of: "/") {
            candidate = String(candidate[..<slash])
        }

        candidate = cleanEndpoint(candidate)
        return candidate
    }

    private static func cleanEndpoint(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\b(open-jaw|business|economy|return|flights?|ferry|boat|cycle|cycling|transfer|drive|driving|hotel|hotels?)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
