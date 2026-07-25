import Foundation

enum AppSettings {
    static let defaultSortOrderKey = "defaultSortOrder"
    static let notificationsEnabledKey = "notificationsEnabled"
    static let hasAskedNotificationPermissionKey = "hasAskedNotificationPermission"
    static let appearanceModeKey = "appearanceMode"
    static let installedFontsSortOrderKey = "installedFontsSortOrder"
    static let googleFontsAPIKeyKey = "googleFontsAPIKey"

    static var notificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: notificationsEnabledKey)
    }

    static var googleFontsAPIKey: String? {
        let value = UserDefaults.standard.string(forKey: googleFontsAPIKeyKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}
