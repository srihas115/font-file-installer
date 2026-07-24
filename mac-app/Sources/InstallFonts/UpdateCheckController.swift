import Foundation

@MainActor
final class UpdateCheckController: ObservableObject {
    @Published var isChecking = false
    @Published var alertTitle = "Updates"
    @Published var alertMessage = ""
    @Published var releaseURL: URL?
    @Published var isShowingAlert = false

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true

        Task {
            do {
                let result = try await UpdateChecker.check()
                if result.isUpdateAvailable {
                    alertTitle = "Update Available"
                    alertMessage = "You have \(result.currentVersion). The latest release is \(result.latestVersion)."
                    releaseURL = result.releaseURL
                } else {
                    alertTitle = "You're Up to Date"
                    alertMessage = "You have \(result.currentVersion), which matches the latest release."
                    releaseURL = nil
                }
            } catch {
                alertTitle = "Couldn't Check for Updates"
                alertMessage = error.localizedDescription
                releaseURL = nil
            }

            isShowingAlert = true
            isChecking = false
        }
    }
}
