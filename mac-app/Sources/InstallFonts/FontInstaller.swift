import Foundation

struct InstallResult {
    var found: [URL] = []
    var installed: [String] = []
    var skipped: [String] = []
    var failed: [(name: String, reason: String)] = []
}

enum FontInstaller {
    static let fontExtensions: Set<String> = ["otf", "ttf", "woff", "woff2"]

    static var userFontsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Fonts", isDirectory: true)
    }

    static func findFontFiles(in folder: URL) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return results
        }

        for case let fileURL as URL in enumerator {
            guard let isRegular = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                  isRegular == true else { continue }
            if fontExtensions.contains(fileURL.pathExtension.lowercased()) {
                results.append(fileURL)
            }
        }
        return results.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func install(from folder: URL, force: Bool) -> InstallResult {
        var result = InstallResult()

        let fontsDir = userFontsDirectory
        let fm = FileManager.default
        try? fm.createDirectory(at: fontsDir, withIntermediateDirectories: true)

        result.found = findFontFiles(in: folder)

        for fontURL in result.found {
            let destURL = fontsDir.appendingPathComponent(fontURL.lastPathComponent)
            let name = fontURL.lastPathComponent

            if fm.fileExists(atPath: destURL.path) {
                if force {
                    do {
                        try fm.removeItem(at: destURL)
                        try fm.copyItem(at: fontURL, to: destURL)
                        result.installed.append(name)
                    } catch {
                        result.failed.append((name, error.localizedDescription))
                    }
                } else {
                    result.skipped.append(name)
                }
                continue
            }

            do {
                try fm.copyItem(at: fontURL, to: destURL)
                result.installed.append(name)
            } catch {
                result.failed.append((name, error.localizedDescription))
            }
        }

        return result
    }
}
