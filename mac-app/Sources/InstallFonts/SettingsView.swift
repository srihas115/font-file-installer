import SwiftUI
import UserNotifications

struct SettingsView: View {
    @AppStorage(AppSettings.defaultSortOrderKey) private var defaultSortOrder = FontSortOrder.popular.rawValue
    @AppStorage(AppSettings.notificationsEnabledKey) private var notificationsEnabled = false

    var body: some View {
        Form {
            Picker("Default sort", selection: $defaultSortOrder) {
                ForEach(FontSortOrder.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option.rawValue)
                }
            }

            Toggle("Install notifications", isOn: notificationsBinding)
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 360)
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
