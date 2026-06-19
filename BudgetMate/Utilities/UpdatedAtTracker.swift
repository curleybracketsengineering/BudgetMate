import Foundation

#if os(macOS)
import Foundation
#else
import UIKit
#endif

enum UpdatedAtTracker {
    static var currentDeviceId: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        UIDevice.current.name
        #endif
    }
}

extension BudgetMonth {
    func markCreated() {
        createdAt = Date()
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }

    func markUpdated() {
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }
}

extension BudgetRule {
    func markCreated() {
        createdAt = Date()
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }

    func markUpdated() {
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }
}

extension BudgetTile {
    func markCreated() {
        createdAt = Date()
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }

    func markUpdated() {
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }
}

extension AppSettings {
    func markCreated() {
        createdAt = Date()
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }

    func markUpdated() {
        updatedAt = Date()
        lastLocalSaveAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }
}

extension PayeeNote {
    func markCreated() {
        createdAt = Date()
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }

    func markUpdated() {
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }
}

extension BankAccount {
    func markCreated() {
        createdAt = Date()
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }

    func markUpdated() {
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }
}

extension Holiday {
    func markCreated() {
        createdAt = Date()
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }

    func markUpdated() {
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }
}

extension HolidayActivity {
    func markCreated() {
        createdAt = Date()
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }

    func markUpdated() {
        updatedAt = Date()
        deviceId = UpdatedAtTracker.currentDeviceId
    }
}
