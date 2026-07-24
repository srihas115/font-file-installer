import SwiftUI

@main
struct InstallFontsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 200, minHeight: 420)
        }
        .defaultSize(width: 340, height: 420)
        .windowResizability(.contentSize)
    }
}
