import SwiftData
import SwiftUI

enum ModelContainerFactory {
  /// CloudKit container: iCloud.com.curlybrackets.budgetmate
  /// Mac and future iPad must use the same container.
  /// Sync is automatic and eventually consistent — no custom sync engine.
  static let cloudKitContainerID = "iCloud.com.curlybrackets.budgetmate"

  static private(set) var activeConfiguration: StoreConfiguration = .cloud

  static let schema = Schema([
    AppSettings.self,
    BankAccount.self,
    BudgetMonth.self,
    BudgetRule.self,
    BudgetRuleSubCategory.self,
    BudgetTile.self,
    Holiday.self,
    HolidayActivity.self,
    PayeeNote.self,
  ])

  static func makeContainer() -> ModelContainer {
    PersistedStoreService.performScheduledPurgeIfNeeded()

    let cloudConfig = ModelConfiguration(
      StoreConfiguration.cloud.rawValue,
      schema: schema,
      cloudKitDatabase: .automatic
    )

    do {
      activeConfiguration = .cloud
      return try ModelContainer(for: schema, configurations: [cloudConfig])
    } catch {
      // Graceful fallback when iCloud is unavailable (simulator, no account signed in).
      print("CloudKit ModelContainer failed: \(error). Falling back to local-only storage.")
      let localConfig = ModelConfiguration(
        StoreConfiguration.local.rawValue,
        schema: schema,
        cloudKitDatabase: .none
      )
      do {
        activeConfiguration = .local
        return try ModelContainer(for: schema, configurations: [localConfig])
      } catch {
        fatalError("Could not create ModelContainer: \(error)")
      }
    }
  }

  static func makeContainer(configuration: StoreConfiguration) -> ModelContainer? {
    let config = ModelConfiguration(
      configuration.rawValue,
      schema: schema,
      cloudKitDatabase: configuration == .cloud ? .automatic : .none
    )
    return try? ModelContainer(for: schema, configurations: [config])
  }
}
