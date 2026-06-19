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
        isProUnlocked ? PlanningHorizon.months(forYears: 10) : PlanningHorizon.baseMonths
    }

    func allowedHorizons() -> [Int] {
        if isProUnlocked {
            return stride(
                from: PlanningHorizon.baseMonths,
                through: maxHorizonMonths(),
                by: PlanningHorizon.monthsPerYear
            ).map { $0 }
        }
        return [PlanningHorizon.baseMonths]
    }

    func canExtendHorizon(currentMonths: Int) -> Bool {
        currentMonths < maxHorizonMonths()
    }

    /// Snaps a stored horizon to the nearest valid option (e.g. legacy 12-month plans → 3 years).
    func normalizedHorizon(_ months: Int) -> Int {
        let allowed = allowedHorizons()
        if allowed.contains(months) { return months }
        if let next = allowed.first(where: { $0 >= months }) { return next }
        return allowed.last ?? PlanningHorizon.baseMonths
    }

    enum ProFeature: String, CaseIterable {
        case extendedForecast
        case scenarios
        case holidayPlanner
        case csvImport
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
            case .extendedForecast: "Extra plan years (4+)"
            case .scenarios: "Scenario planning"
            case .holidayPlanner: "Holiday & event planner"
            case .csvImport: "CSV / QBO import"
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
             .impactView, .largePaymentWarnings, .ruleExpiryWarnings,
             .yearlySummary, .plannedVsActual, .export, .confidenceLevels, .explainThisMonth:
            return isProUnlocked
        }
    }

    /// iCloud sync is always free per product spec.
    var isCloudSyncAvailable: Bool { true }
}
