import Foundation

enum ConfidenceLevel: String, Codable, CaseIterable, Identifiable {
    case known
    case estimated
    case guess
    case imported
    case aiSuggested

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .known: "Known"
        case .estimated: "Estimated"
        case .guess: "Guess"
        case .imported: "Imported"
        case .aiSuggested: "AI suggested"
        }
    }
}
