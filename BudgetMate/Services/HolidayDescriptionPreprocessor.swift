import Foundation

enum HolidayDescriptionPreprocessor {
    static let defaultMaxCharacters = 14_000

    static func preprocess(_ raw: String, maxCharacters: Int = defaultMaxCharacters) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = stripImageMarkdown(text)
        text = inlineFootnoteLinks(text)
        text = prioritizeAndTruncate(text, maxCharacters: maxCharacters)
        return text
    }

    private static func stripImageMarkdown(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\([^)]*\)"#, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private static func inlineFootnoteLinks(_ text: String) -> String {
        var definitions: [String: (label: String, url: String)] = [:]

        let defPattern = #"^\[(\d+)\]:\s+(\S+)(?:\s+"([^"]*)")?\s*$"#
        guard let defRegex = try? NSRegularExpression(pattern: defPattern, options: [.anchorsMatchLines]) else {
            return text
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        defRegex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match,
                  match.numberOfRanges >= 3,
                  let idRange = Range(match.range(at: 1), in: text),
                  let urlRange = Range(match.range(at: 2), in: text) else { return }
            let id = String(text[idRange])
            let url = String(text[urlRange])
            var label = url
            if match.numberOfRanges >= 4,
               match.range(at: 3).location != NSNotFound,
               let titleRange = Range(match.range(at: 3), in: text) {
                let title = String(text[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { label = title }
            }
            definitions[id] = (label: label, url: url)
        }

        guard !definitions.isEmpty else { return text }

        var result = text
        let refPattern = #"\[([^\]]+)\]\[(\d+)\]"#
        guard let refRegex = try? NSRegularExpression(pattern: refPattern, options: []) else {
            return text
        }

        let matches = refRegex.matches(in: result, options: [], range: NSRange(result.startIndex..<result.endIndex, in: result))
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range, in: result),
                  let labelRange = Range(match.range(at: 1), in: result),
                  let idRange = Range(match.range(at: 2), in: result) else { continue }
            let label = String(result[labelRange])
            let id = String(result[idRange])
            guard let definition = definitions[id] else { continue }
            let linkLabel = label.isEmpty ? definition.label : label
            let replacement = "[\(linkLabel)](\(definition.url))"
            result.replaceSubrange(fullRange, with: replacement)
        }

        if let defRegex = try? NSRegularExpression(pattern: defPattern, options: [.anchorsMatchLines]) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = defRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func prioritizeAndTruncate(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }

        var sections: [String] = []

        if let route = extractSection(matching: #"(?im)^#+\s*(recommended route|qatar version|rebuilt day-by-day)"#, in: text, maxLength: 2_500) {
            sections.append(route)
        }

        if let budget = extractBudgetSection(in: text, maxLength: 2_500) {
            sections.append(budget)
        }

        if let itinerary = extractDayByDaySection(in: text, maxLength: 8_000) {
            sections.append(itinerary)
        }

        if sections.isEmpty {
            return String(text.prefix(maxCharacters))
        }

        var combined = sections.joined(separator: "\n\n---\n\n")
        if combined.count > maxCharacters {
            combined = String(combined.prefix(maxCharacters))
        }
        return combined
    }

    private static func extractSection(matching pattern: String, in text: String, maxLength: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)),
              let startRange = Range(match.range, in: text) else { return nil }
        let start = startRange.lowerBound
        let remainder = text[start...]
        let chunk = String(remainder.prefix(maxLength))
        return chunk.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func extractBudgetSection(in text: String, maxLength: Int) -> String? {
        guard let range = text.range(of: "Updated realistic budget", options: .caseInsensitive)
            ?? text.range(of: "| Component", options: .caseInsensitive) else { return nil }
        let chunk = String(text[range.lowerBound...].prefix(maxLength))
        return chunk.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func extractDayByDaySection(in text: String, maxLength: Int) -> String? {
        guard let range = text.range(of: "Rebuilt day-by-day", options: .caseInsensitive)
            ?? text.range(of: "day-by-day itinerary", options: .caseInsensitive) else { return nil }

        let section = String(text[range.lowerBound...])
        var lines: [String] = []
        var currentLength = 0

        for line in section.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isHeader = trimmed.hasPrefix("## ")
            let isSubHeader = trimmed.hasPrefix("### ")
            let includeLine = isHeader || isSubHeader || !lines.isEmpty

            guard includeLine else { continue }
            if currentLength + line.count + 1 > maxLength, !isHeader, !isSubHeader { break }

            lines.append(line)
            currentLength += line.count + 1

            if isHeader, currentLength > maxLength / 2 { break }
        }

        let chunk = lines.joined(separator: "\n")
        return chunk.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
