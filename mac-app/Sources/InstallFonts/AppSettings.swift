import Foundation

enum AppSettings {
    static let defaultSortOrderKey = "defaultSortOrder"
    static let notificationsEnabledKey = "notificationsEnabled"
    static let hasAskedNotificationPermissionKey = "hasAskedNotificationPermission"

    static var notificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: notificationsEnabledKey)
    }
}
