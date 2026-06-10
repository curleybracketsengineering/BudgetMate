import SwiftUI
import SwiftData

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]

    @State private var selection: NavigationSection? = .monthlyPlan
    @State private var selectedMonth: BudgetMonth?
    @State private var showingFirstRun = false

    var body: some View {
        NavigationSplitView {
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
            BudgetRulesListView()
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
        if selection == .monthlyPlan, let selectedMonth {
            MonthDetailView(month: selectedMonth)
        } else {
            ContentUnavailableView(
                selection == .monthlyPlan ? "Select a month" : "No detail",
                systemImage: "calendar",
                description: Text(selection == .monthlyPlan ? "Click a month card to view details." : "This section has no detail pane.")
            )
        }
    }

    private func checkFirstRun() {
        if settingsList.isEmpty {
            showingFirstRun = true
        }
    }
}
