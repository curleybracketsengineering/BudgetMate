import Foundation
import Observation

@Observable
final class FeatureGateService {
    private let proUnlockedKey = "budgetmate.isProUnlocked"

    var isProUnlocked: Bool {
        get { UserDefaults.standard.bool(forKey: proUnlockedKey) }
        set { UserDefaults.standard.set(newValue, forKey: proUnlockedKey) }
    }

    func maxHorizonMonths() -> Int {
        isProUnlocked ? 60 : 12
    }

    func allowedHorizons() -> [Int] {
        if isProUnlocked {
            return [12, 24, 36, 60]
        }
        return [12]
    }

    enum ProFeature: String, CaseIterable {
        case extendedForecast
        case scenarios
        case holidayPlanner
        case csvImport
        case aiAssistant
        case impactView
        case largePaymentWarnings
        case ruleExpiryWarnings
        case yearlySummary
        case plannedVsActual
        case export
        case confidenceLevels
        case explainThisMonth

        var displayName: String {
            switch self {
            case .extendedForecast: "36/60-month forecast"
            case .scenarios: "Scenario planning"
            case .holidayPlanner: "Holiday & event planner"
            case .csvImport: "CSV / QBO import"
            case .aiAssistant: "AI Budget Assistant"
            case .impactView: "What changed / impact view"
            case .largePaymentWarnings: "Large payment warnings"
            case .ruleExpiryWarnings: "Rule expiry warnings"
            case .yearlySummary: "Yearly summaries"
            case .plannedVsActual: "Planned vs actual"
            case .export: "Export CSV/PDF"
            case .confidenceLevels: "Confidence levels"
            case .explainThisMonth: "Explain this month"
            }
        }
    }

    func isAvailable(_ feature: ProFeature) -> Bool {
        switch feature {
        case .extendedForecast, .scenarios, .holidayPlanner, .csvImport,
             .aiAssistant, .impactView, .largePaymentWarnings, .ruleExpiryWarnings,
             .yearlySummary, .plannedVsActual, .export, .confidenceLevels, .explainThisMonth:
            return isProUnlocked
        }
    }

    /// iCloud sync is always free per product spec.
    var isCloudSyncAvailable: Bool { true }
}
