import Foundation
import UserNotifications

enum InstallNotifier {
    static func notify(result: InstallResult) {
        guard AppSettings.notificationsEnabled else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                deliver(result, through: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    deliver(result, through: center)
                }
            case .denied:
                return
            @unknown default:
                return
            }
        }
    }

    private static func deliver(_ result: InstallResult, through center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "Font Installer"
        content.body = "Installed \(result.installed.count) font\(result.installed.count == 1 ? "" : "s"). Skipped \(result.skipped.count). Failed \(result.failed.count)."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "font-install-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
