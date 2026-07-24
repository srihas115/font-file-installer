import Foundation

struct UpdateCheckResult {
    let currentVersion: String
    let latestVersion: String
    let releaseURL: URL

    var isUpdateAvailable: Bool {
        UpdateChecker.isNewerVersion(latestVersion, than: currentVersion)
    }
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let htmlURL: URL?

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

enum UpdateChecker {
    static let releasesURL = URL(string: "https://github.com/srihas115/font-file-installer/releases/latest")!
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/srihas115/font-file-installer/releases/latest")!
    private static let userAgent = "font-file-installer-macOS/1.0"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static func check() async throws -> UpdateCheckResult {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let release = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)

        return UpdateCheckResult(
            currentVersion: currentVersion,
            latestVersion: release.tagName,
            releaseURL: release.htmlURL ?? releasesURL
        )
    }

    static func isNewerVersion(_ latest: String, than current: String) -> Bool {
        let latestParts = versionParts(latest)
        let currentParts = versionParts(current)
        let count = max(latestParts.count, currentParts.count)

        for index in 0..<count {
            let latestValue = index < latestParts.count ? latestParts[index] : 0
            let currentValue = index < currentParts.count ? currentParts[index] : 0
            if latestValue != currentValue {
                return latestValue > currentValue
            }
        }

        return false
    }

    private static func versionParts(_ version: String) -> [Int] {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        return trimmed
            .split { character in
                character == "." || character == "-"
            }
            .prefix { part in
                Int(part) != nil
            }
            .compactMap { Int($0) }
    }
}
