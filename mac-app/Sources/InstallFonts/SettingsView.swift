import SwiftUI
import UserNotifications

struct SettingsView: View {
    @AppStorage(AppSettings.defaultSortOrderKey) private var defaultSortOrder = FontSortOrder.popular.rawValue
    @AppStorage(AppSettings.notificationsEnabledKey) private var notificationsEnabled = false
    @AppStorage(AppSettings.appearanceModeKey) private var appearanceMode = AppearanceMode.dark.rawValue
    @AppStorage(AppSettings.installedFontsSortOrderKey) private var installedFontsSortOrder = InstalledFontsSortOrder.recentlyInstalled.rawValue

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option.rawValue)
                }
            }

            Picker("Default sort", selection: $defaultSortOrder) {
                ForEach(FontSortOrder.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option.rawValue)
                }
            }

            Picker("Installed fonts sort", selection: $installedFontsSortOrder) {
                ForEach(InstalledFontsSortOrder.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option.rawValue)
                }
            }

            Toggle("Install notifications", isOn: notificationsBinding)
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 420)
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { notificationsEnabled },
            set: { isOn in
                notificationsEnabled = isOn
                if isOn {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        if !granted {
                            DispatchQueue.main.async {
                                notificationsEnabled = false
                            }
                        }
                    }
                }
            }
        )
    }
}
