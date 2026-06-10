//
//  BudgetMateApp.swift
//  BudgetMate
//

import SwiftUI
import SwiftData

@main
struct BudgetMateApp: App {
    @State private var featureGate = FeatureGateService()
    @State private var importSession = ImportSessionStore()

    private let modelContainer = ModelContainerFactory.makeContainer()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(featureGate)
                .environment(importSession)
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
    }
}
