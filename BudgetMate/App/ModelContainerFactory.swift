import SwiftData
import SwiftUI

enum ModelContainerFactory {
  /// CloudKit container: iCloud.com.curlybrackets.budgetmate
  /// Mac and future iPad must use the same container.
  /// Sync is automatic and eventually consistent — no custom sync engine.
  static let cloudKitContainerID = "iCloud.com.curlybrackets.budgetmate"

  static let schema = Schema([
    AppSettings.self,
    BankAccount.self,
    BudgetMonth.self,
    BudgetRule.self,
    BudgetTile.self,
    PayeeNote.self,
  ])

  static func makeContainer() -> ModelContainer {
    let cloudConfig = ModelConfiguration(
      "BudgetMateCloud",
      schema: schema,
      cloudKitDatabase: .automatic
    )

    do {
      return try ModelContainer(for: schema, configurations: [cloudConfig])
    } catch {
      // Graceful fallback when iCloud is unavailable (simulator, no account signed in).
      print("CloudKit ModelContainer failed: \(error). Falling back to local-only storage.")
      let localConfig = ModelConfiguration(
        "BudgetMateLocal",
        schema: schema,
        cloudKitDatabase: .none
      )
      do {
        return try ModelContainer(for: schema, configurations: [localConfig])
      } catch {
        fatalError("Could not create ModelContainer: \(error)")
      }
    }
  }
}
