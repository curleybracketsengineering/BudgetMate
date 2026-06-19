import SwiftUI
import SwiftData

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]

    @State private var selection: NavigationSection? = .monthlyPlan
    @State private var selectedMonth: BudgetMonth?
    @State private var selectedBudgetRule: BudgetRule?
    @State private var selectedHoliday: Holiday?
    @State private var showingFirstRun = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var storeRecoveryMessage: String?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                ForEach(NavigationSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .navigationTitle("BudgetMate")
            .listStyle(.sidebar)
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .onAppear {
            checkFirstRun()
            BudgetRuleSubCategoryService.migrateLegacyCategoriesIfNeeded(in: modelContext)
            attemptStoreRecovery()
        }
        .alert("Data restored", isPresented: recoveryAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(storeRecoveryMessage ?? "")
        }
        .onChange(of: selection) {
            if selection != .monthlyPlan  {
                selectedMonth = nil
            }
            if selection != .budgetRules {
                selectedBudgetRule = nil
            }
            if selection != .holidays {
                selectedHoliday = nil
            }
        }
        .sheet(isPresented: $showingFirstRun) {
            FirstRunSetupView()
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch selection {
        case .dashboard:
            DashboardView()
        case .monthlyPlan:
            MonthlyPlanView(selectedMonth: $selectedMonth)
        case .budgetRules:
            BudgetRulesListView(selectedRule: $selectedBudgetRule)
        case .holidays:
            HolidaysView(selectedHoliday: $selectedHoliday)
        case .imports:
            ImportsView()
        case .settings:
            SettingsView()
        case .none:
            ContentUnavailableView("Select a section", systemImage: "sidebar.left")
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch selection {
        case .monthlyPlan:
            if let selectedMonth {
                MonthDetailView(month: selectedMonth)
            } else {
                ContentUnavailableView(
                    "Select a month",
                    systemImage: "calendar",
                    description: Text("Click a month card to view details.")
                )
            }
        case .budgetRules:
            if let selectedBudgetRule {
                BudgetRuleDetailView(rule: selectedBudgetRule) {
                    self.selectedBudgetRule = nil
                }
            } else {
                ContentUnavailableView(
                    "Select a rule",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text("Choose a rule to see its monthly impact and details.")
                )
            }
        case .holidays:
            if let selectedHoliday {
                HolidayDetailView(holiday: selectedHoliday) {
                    self.selectedHoliday = nil
                }
            } else {
                ContentUnavailableView(
                    "Select a holiday",
                    systemImage: "airplane",
                    description: Text("Choose a trip to plan activities and add costs to your forecast.")
                )
            }
        default:
            EmptyView()
        }
    }

    private func checkFirstRun() {
        if settingsList.isEmpty {
            showingFirstRun = true
        }
    }

    private var recoveryAlertPresented: Binding<Bool> {
        Binding(
            get: { storeRecoveryMessage != nil },
            set: { if !$0 { storeRecoveryMessage = nil } }
        )
    }

    private func attemptStoreRecovery() {
        do {
            guard let result = try StoreRecoveryService.recoverFromAlternateStoreIfNeeded(
                in: modelContext,
                activeConfiguration: ModelContainerFactory.activeConfiguration
            ), result.didRecover else { return }

            storeRecoveryMessage = """
            Recovered data from your \(result.source == .cloud ? "iCloud" : "local") database: \
            \(result.rulesAdded) rules, \(result.tilesAdded) tiles, \(result.monthsAdded) months.
            """
        } catch {
            print("Store recovery failed: \(error)")
        }
    }
}
