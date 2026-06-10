import Foundation

enum CommitmentType: String, Codable, CaseIterable, Identifiable {
    case known
    case flexible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .known: "Known commitment"
        case .flexible: "Flexible spending"
        }
    }
}
