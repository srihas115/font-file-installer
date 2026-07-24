import SwiftUI

@main
struct InstallFontsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var updateController = UpdateCheckController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(updateController)
                .frame(minWidth: 600, maxWidth: 760, minHeight: 430, maxHeight: 520)
        }
        .defaultSize(width: 650, height: 430)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Font Installer") {
                    openWindow(id: "about")
                }
            }
            CommandGroup(after: .appInfo) {
                Button(updateController.isChecking ? "Checking for updates..." : "Check for updates") {
                    updateController.checkForUpdates()
                }
                .disabled(updateController.isChecking)
            }
        }

        Window("About Font Installer", id: "about") {
            AboutView()
        }
        .defaultSize(width: 300, height: 230)
        .windowResizability(.contentSize)
    }
}
