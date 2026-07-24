import SwiftUI

@main
struct InstallFontsApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var updateController = UpdateCheckController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(updateController)
                .frame(minWidth: 600, minHeight: 300)
        }
        .defaultSize(width: 650, height: 320)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Install Fonts") {
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

        Window("About Install Fonts", id: "about") {
            AboutView()
        }
        .defaultSize(width: 284, height: 210)
        .windowResizability(.contentSize)
    }
}
