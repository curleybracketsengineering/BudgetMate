import Foundation

enum NavigationSection: String, CaseIterable, Identifiable {
    case dashboard
    case monthlyPlan
    case budgetRules
    case holidays
    case imports
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .monthlyPlan: "Monthly Plan"
        case .budgetRules: "Budget Rules"
        case .holidays: "Holidays & Events"
        case .imports: "Imports"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.line.uptrend.xyaxis"
        case .monthlyPlan: "calendar"
        case .budgetRules: "arrow.triangle.2.circlepath"
        case .holidays: "airplane"
        case .imports: "square.and.arrow.down"
        case .settings: "gearshape"
        }
    }
}
