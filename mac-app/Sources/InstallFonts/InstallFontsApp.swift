import SwiftUI

@main
struct InstallFontsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 300)
        }
        .defaultSize(width: 650, height: 320)
        .windowResizability(.contentSize)
    }
}
