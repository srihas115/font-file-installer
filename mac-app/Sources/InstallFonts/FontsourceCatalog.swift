import Foundation

struct FontsourceFamily: Decodable, Identifiable, Hashable {
    let id: String
    let family: String
    let category: String
    let weights: [Int]
    let styles: [String]
    let defSubset: String
}

private struct FontsourceFontDetail: Decodable {
    let id: String
    let family: String
    let defSubset: String
    let variants: [String: [String: [String: FontsourceVariantFile]]]
}

private struct FontsourceVariantFile: Decodable {
    let url: [String: URL]
}

struct FontsourceFileEntry {
    let weight: Int
    let italic: Bool
    let subset: String
    let fileURL: URL
}

enum FontsourceCatalog {
    private static let fontsURL = URL(string: "https://api.fontsource.org/v1/fonts")!
    private static let userAgent = "font-file-installer-macOS/1.0"

    enum FontsourceError: LocalizedError {
        case invalidResponse
        case noFiles

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Fontsource returned an unexpected response."
            case .noFiles:
                return "Fontsource did not return installable font files for that selection."
            }
        }
    }

    static func loadCatalog() async throws -> [FontsourceFamily] {
        var request = URLRequest(url: fontsURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([FontsourceFamily].self, from: data)
            .sorted { $0.family < $1.family }
    }

    static func resolveFontFiles(family: FontsourceFamily, weights: [FontWeight]) async throws -> [FontsourceFileEntry] {
        let detailURL = fontsURL.appendingPathComponent(family.id)
        var request = URLRequest(url: detailURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let detail = try JSONDecoder().decode(FontsourceFontDetail.self, from: data)

        let entries = weights.compactMap { requested -> FontsourceFileEntry? in
            let weightKey = String(requested.weight)
            let styleKey = requested.italic ? "italic" : "normal"
            guard let styleVariants = detail.variants[weightKey]?[styleKey] else {
                return nil
            }

            let subset = styleVariants[detail.defSubset] != nil
                ? detail.defSubset
                : styleVariants.keys.sorted().first
            guard
                let subset,
                let urls = styleVariants[subset]?.url,
                let fileURL = urls["ttf"] ?? urls["woff2"] ?? urls["woff"]
            else {
                return nil
            }

            return FontsourceFileEntry(
                weight: requested.weight,
                italic: requested.italic,
                subset: subset,
                fileURL: fileURL
            )
        }

        guard !entries.isEmpty else {
            throw FontsourceError.noFiles
        }

        return entries
    }

    static func downloadFonts(_ entries: [FontsourceFileEntry], family: String) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallFonts-Fontsource-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let safeFamily = family.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let safeFamilyName = safeFamily.isEmpty ? "Font" : safeFamily

        for entry in entries {
            var request = URLRequest(url: entry.fileURL)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)

            let ext = entry.fileURL.pathExtension.isEmpty ? "ttf" : entry.fileURL.pathExtension
            let styleSuffix = entry.italic ? "Italic" : ""
            let filename = "\(safeFamilyName)-\(entry.subset)-\(entry.weight)\(styleSuffix).\(ext)"
            try data.write(to: tempDir.appendingPathComponent(filename))
        }

        return tempDir
    }
}
