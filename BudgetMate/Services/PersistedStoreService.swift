import Foundation

enum PersistedStoreService {
    static let purgeOnNextLaunchKey = "budgetMatePurgeStoresOnNextLaunch"
    static let legacySubCategoryMigrationKey = "budgetRuleSubCategoryMigrationV1"

    static var applicationSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    /// Deletes every on-disk store (local + iCloud), including CloudKit auxiliary files.
    static func purgeAllStoreFilesOnDisk() {
        let fileManager = FileManager.default
        let support = applicationSupportURL

        for baseName in StoreConfiguration.allBaseNames {
            for suffix in storeSuffixes {
                let url = support.appendingPathComponent("\(baseName).store\(suffix)")
                try? fileManager.removeItem(at: url)
            }
        }

        for name in auxiliaryDirectoryNames {
            try? fileManager.removeItem(at: support.appendingPathComponent(name))
        }
    }

    /// Deletes store files for every configuration except the one currently in use.
    static func purgeInactiveStoreFiles(keeping active: StoreConfiguration) {
        let fileManager = FileManager.default
        let support = applicationSupportURL

        for baseName in StoreConfiguration.allBaseNames where baseName != active.rawValue {
            for suffix in storeSuffixes {
                let url = support.appendingPathComponent("\(baseName).store\(suffix)")
                try? fileManager.removeItem(at: url)
            }
        }

        if active == .local {
            for name in auxiliaryDirectoryNames {
                try? fileManager.removeItem(at: support.appendingPathComponent(name))
            }
        }
    }

    static func scheduleFullStorePurgeOnNextLaunch() {
        UserDefaults.standard.set(true, forKey: purgeOnNextLaunchKey)
    }

    static func performScheduledPurgeIfNeeded() {
        guard UserDefaults.standard.bool(forKey: purgeOnNextLaunchKey) else { return }
        purgeAllStoreFilesOnDisk()
        UserDefaults.standard.set(false, forKey: purgeOnNextLaunchKey)
        resetAuxiliaryPreferences()
    }

    static func resetAuxiliaryPreferences() {
        UserDefaults.standard.removeObject(forKey: legacySubCategoryMigrationKey)
    }

    private static let storeSuffixes = ["", "-wal", "-shm"]

    private static let auxiliaryDirectoryNames = [
        ".BudgetMateCloud_SUPPORT",
        "BudgetMateCloud_ckAssets",
        "BudgetMate",
    ]
}

extension StoreConfiguration {
    static var allBaseNames: [String] {
        [StoreConfiguration.cloud.rawValue, StoreConfiguration.local.rawValue]
    }
}
