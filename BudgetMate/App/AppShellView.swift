import SwiftUI
import SwiftData

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]

    @State private var selection: NavigationSection? = .monthlyPlan
    @State private var selectedMonth: BudgetMonth?
    @State private var selectedBudgetRule: BudgetRule?
    @State private var showingFirstRun = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
        .onAppear { checkFirstRun() }
        .onChange(of: selection) {
            if selection != .monthlyPlan {
                selectedMonth = nil
            }
            if selection != .budgetRules {
                selectedBudgetRule = nil
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
            HolidaysView()
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
        default:
            EmptyView()
        }
    }

    private func checkFirstRun() {
        if settingsList.isEmpty {
            showingFirstRun = true
        }
    }
}
