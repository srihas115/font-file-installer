import Foundation

/// A single Google Fonts family, as described by the public metadata catalog.
struct FontFamily: Decodable, Identifiable, Hashable {
    var family: String
    var category: String
    var variants: [String]
    var subsets: [String]

    var id: String { family }

    private enum CodingKeys: String, CodingKey {
        case family
        case category
        case variants
        case subsets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        family = try container.decode(String.self, forKey: .family)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "unknown"
        variants = try container.decodeIfPresent([String].self, forKey: .variants) ?? ["regular"]
        subsets = try container.decodeIfPresent([String].self, forKey: .subsets) ?? []
    }
}

private struct FontFamilyMetadataResponse: Decodable {
    var familyMetadataList: [FontFamily]
}

/// A single weight/style combination to request from the css2 API.
struct FontWeight: Hashable {
    var weight: Int
    var italic: Bool
}

/// One resolved `@font-face` entry: a specific weight/style and the file that serves it.
struct FontFaceEntry {
    let weight: Int
    let italic: Bool
    let fileURL: URL
}

/// Fetches and downloads fonts from Google's public (unofficial, no-API-key) endpoints —
/// the same ones fonts.google.com's own website uses. There is no versioned, documented
/// API for these, so callers should treat failures as recoverable (fall back to the
/// folder/zip flow) rather than fatal.
enum GoogleFontsCatalog {
    static let userAgent = "font-file-installer-macOS/1.0"
    private static let metadataURL = URL(string: "https://fonts.google.com/metadata/fonts")!
    private static let css2URLString = "https://fonts.googleapis.com/css2"
    private static let catalogCacheTTL: TimeInterval = 7 * 24 * 3600

    enum CatalogError: LocalizedError {
        case unreachable(Error)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .unreachable(let error):
                return "Could not reach the Google Fonts catalog: \(error.localizedDescription)"
            case .invalidResponse:
                return "Google Fonts returned an unexpected response."
            }
        }
    }

    private static var cacheFileURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("font-file-installer/google-fonts-metadata.json")
    }

    /// Loads the family catalog, using a cached copy (up to a week old) when possible.
    /// Falls back to a stale cache on network failure rather than throwing, if one exists.
    static func loadCatalog(forceRefresh: Bool = false) async throws -> [FontFamily] {
        let cacheURL = cacheFileURL

        if !forceRefresh, isFresh(cacheURL), let cached = try? cachedCatalog(at: cacheURL) {
            return cached
        }

        do {
            var request = URLRequest(url: metadataURL)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            let families = try parseCatalog(data)
            try? persistCache(data, at: cacheURL)
            return families
        } catch {
            if let cached = try? cachedCatalog(at: cacheURL) {
                return cached
            }
            throw CatalogError.unreachable(error)
        }
    }

    private static func isFresh(_ url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < catalogCacheTTL
    }

    private static func cachedCatalog(at url: URL) throws -> [FontFamily] {
        let data = try Data(contentsOf: url)
        return try parseCatalog(data)
    }

    private static func persistCache(_ data: Data, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    /// The metadata response is prefixed with a `)]}'` XSSI-protection line that must be
    /// stripped before it's valid JSON.
    private static func parseCatalog(_ data: Data) throws -> [FontFamily] {
        guard var text = String(data: data, encoding: .utf8) else {
            throw CatalogError.invalidResponse
        }
        if text.hasPrefix(")]}'") {
            if let newlineIndex = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: newlineIndex)...])
            } else {
                text = "{}"
            }
        }
        guard let strippedData = text.data(using: .utf8) else {
            throw CatalogError.invalidResponse
        }
        let response = try JSONDecoder().decode(FontFamilyMetadataResponse.self, from: strippedData)
        return response.familyMetadataList.sorted { $0.family < $1.family }
    }

    /// Builds a css2 delivery URL for a family + set of weight/style combinations.
    /// Requesting with a non-browser User-Agent (the default for both URLSession and
    /// urllib) returns raw TTF files rather than WOFF2 — exactly the installable format
    /// this app needs, with no User-Agent spoofing required.
    static func cssURL(family: String, weights: [FontWeight]) -> URL {
        let familyPlusEncoded = family.replacingOccurrences(of: " ", with: "+")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+-_."))
        let familyEncoded = familyPlusEncoded.addingPercentEncoding(withAllowedCharacters: allowed)
            ?? familyPlusEncoded

        let hasItalic = weights.contains { $0.italic }
        let axis: String
        if hasItalic {
            let pairs = Array(Set(weights)).sorted {
                ($0.italic ? 1 : 0, $0.weight) < ($1.italic ? 1 : 0, $1.weight)
            }
            axis = "ital,wght@" + pairs.map { "\($0.italic ? 1 : 0),\($0.weight)" }.joined(separator: ";")
        } else {
            let distinctWeights = Array(Set(weights.map(\.weight))).sorted()
            axis = "wght@" + distinctWeights.map(String.init).joined(separator: ";")
        }

        let urlString = "\(css2URLString)?family=\(familyEncoded):\(axis)&display=swap"
        guard let url = URL(string: urlString) else {
            preconditionFailure("Failed to build Google Fonts css2 URL for \(family)")
        }
        return url
    }

    /// Fetches the css2 stylesheet for a family and parses out the individual font file URLs.
    static func resolveFontFiles(family: String, weights: [FontWeight]) async throws -> [FontFaceEntry] {
        var request = URLRequest(url: cssURL(family: family, weights: weights))
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let cssText = String(data: data, encoding: .utf8) else {
            throw CatalogError.invalidResponse
        }
        return parseCSS(cssText)
    }

    private static func parseCSS(_ css: String) -> [FontFaceEntry] {
        guard
            let blockPattern = try? NSRegularExpression(
                pattern: "@font-face\\s*\\{([^}]*)\\}",
                options: [.dotMatchesLineSeparators]
            ),
            let weightPattern = try? NSRegularExpression(pattern: "font-weight:\\s*(\\d+)"),
            let stylePattern = try? NSRegularExpression(pattern: "font-style:\\s*(\\w+)"),
            let urlPattern = try? NSRegularExpression(
                pattern: "url\\((https://fonts\\.gstatic\\.com/[^)]+)\\)"
            )
        else {
            return []
        }

        var entries: [FontFaceEntry] = []
        let nsCSS = css as NSString
        let blockMatches = blockPattern.matches(in: css, range: NSRange(location: 0, length: nsCSS.length))

        for match in blockMatches {
            let block = nsCSS.substring(with: match.range(at: 1))
            let nsBlock = block as NSString
            let fullRange = NSRange(location: 0, length: nsBlock.length)

            guard
                let weightMatch = weightPattern.firstMatch(in: block, range: fullRange),
                let urlMatch = urlPattern.firstMatch(in: block, range: fullRange),
                let weight = Int(nsBlock.substring(with: weightMatch.range(at: 1))),
                let fileURL = URL(string: nsBlock.substring(with: urlMatch.range(at: 1)))
            else {
                continue
            }

            let styleMatch = stylePattern.firstMatch(in: block, range: fullRange)
            let isItalic = styleMatch.map { nsBlock.substring(with: $0.range(at: 1)) == "italic" } ?? false

            entries.append(FontFaceEntry(weight: weight, italic: isItalic, fileURL: fileURL))
        }

        return entries
    }

    /// Downloads resolved font files into a fresh temp directory, ready to hand to
    /// `FontInstaller.install(from:force:)` unchanged. Callers are responsible for
    /// removing the returned directory once the install completes.
    static func downloadFonts(_ entries: [FontFaceEntry], family: String) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallFonts-GoogleFonts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let safeFamily = family.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let safeFamilyName = safeFamily.isEmpty ? "Font" : safeFamily

        for entry in entries {
            var request = URLRequest(url: entry.fileURL)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)

            let ext = entry.fileURL.pathExtension.isEmpty ? "ttf" : entry.fileURL.pathExtension
            let styleSuffix = entry.italic ? "Italic" : ""
            let filename = "\(safeFamilyName)-\(entry.weight)\(styleSuffix).\(ext)"
            try data.write(to: tempDir.appendingPathComponent(filename))
        }

        return tempDir
    }
}
