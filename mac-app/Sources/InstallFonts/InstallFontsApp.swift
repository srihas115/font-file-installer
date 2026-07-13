import SwiftUI

@main
struct InstallFontsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 480, minHeight: 420)
        }
        .windowResizability(.contentSize)
    }
}
