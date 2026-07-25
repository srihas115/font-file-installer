import Foundation

enum InstalledFontLookup {
    static func normalizedFamilyName(_ name: String) -> String {
        name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    static func installedFamilyNames() -> Set<String> {
        var names = Set<String>()

        for record in InstalledFontRegistry.records().values {
            if let family = familyName(fromSource: record.source) {
                names.insert(normalizedFamilyName(family))
            }
        }

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: FontInstaller.userFontsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in urls where FontInstaller.fontExtensions.contains(url.pathExtension.lowercased()) {
            if let family = FontMetadataReader.metadata(for: url).familyName {
                names.insert(normalizedFamilyName(family))
            } else {
                names.insert(normalizedFamilyName(fallbackFamilyName(from: url.lastPathComponent)))
            }
        }

        return names
    }

    private static func familyName(fromSource source: String) -> String? {
        let separators = ["Google Fonts · ", "Fontsource · "]
        for separator in separators where source.hasPrefix(separator) {
            return String(source.dropFirst(separator.count))
        }
        return nil
    }

    private static func fallbackFamilyName(from fileName: String) -> String {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        guard parts.count > 1 else { return stem }

        var familyTokens = parts
        while let last = familyTokens.last, isStyleToken(last) {
            familyTokens.removeLast()
        }

        return familyTokens.isEmpty ? stem : familyTokens.joined(separator: " ")
    }

    private static func isStyleToken(_ token: String) -> Bool {
        Int(token) != nil || ["italic", "regular", "bold", "light", "medium", "thin", "black"].contains(token.lowercased())
    }
}
