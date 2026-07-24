import SwiftUI

@main
struct InstallFontsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 500, minHeight: 300)
        }
        .defaultSize(width: 550, height: 320)
        .windowResizability(.contentSize)
    }
}
