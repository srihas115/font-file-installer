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

    /// If `source` is a .zip file, extracts it to a temporary directory and returns that
    /// directory along with a URL to clean up afterward. Otherwise returns `source` as-is.
    static func resolveSourceDirectory(_ source: URL) throws -> (directory: URL, cleanupURL: URL?) {
        guard source.pathExtension.lowercased() == "zip" else {
            return (source, nil)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallFonts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", source.path, tempDir.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: tempDir)
            throw NSError(
                domain: "InstallFonts",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "Could not unzip file."]
            )
        }

        return (tempDir, tempDir)
    }

    static func install(from source: URL, force: Bool) -> InstallResult {
        var result = InstallResult()

        let fontsDir = userFontsDirectory
        let fm = FileManager.default
        try? fm.createDirectory(at: fontsDir, withIntermediateDirectories: true)

        let folder: URL
        let cleanupURL: URL?
        do {
            (folder, cleanupURL) = try resolveSourceDirectory(source)
        } catch {
            result.failed.append((source.lastPathComponent, error.localizedDescription))
            return result
        }
        defer {
            if let cleanupURL {
                try? fm.removeItem(at: cleanupURL)
            }
        }

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
