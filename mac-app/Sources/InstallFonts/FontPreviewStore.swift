import AppKit
import CoreText
import Foundation
import SwiftUI

@MainActor
final class FontPreviewStore: ObservableObject {
    enum FontKey: Hashable {
        case google(String)
        case fontsource(String)
    }

    @Published private var previewFontNames: [FontKey: String] = [:]
    private var loadingFontKeys: Set<FontKey> = []

    func fontName(for key: FontKey) -> String? {
        previewFontNames[key]
    }

    func loadGooglePreview(for family: FontFamily) {
        let key = FontKey.google(family.id)
        guard previewFontNames[key] == nil, !loadingFontKeys.contains(key) else { return }
        loadingFontKeys.insert(key)

        Task {
            defer { loadingFontKeys.remove(key) }

            do {
                let entries = try await GoogleFontsCatalog.resolveFontFiles(
                    family: family.family,
                    weights: [previewWeight(for: family)]
                )
                guard let entry = entries.first else { return }
                let fontName = try await downloadAndRegisterPreviewFont(
                    from: entry.fileURL,
                    cacheName: "google-\(family.id)"
                )
                previewFontNames[key] = fontName
            } catch {
                // Keep the list quiet; preview loading is best-effort.
            }
        }
    }

    func loadFontsourcePreview(for family: FontsourceFamily) {
        let key = FontKey.fontsource(family.id)
        guard previewFontNames[key] == nil, !loadingFontKeys.contains(key) else { return }
        loadingFontKeys.insert(key)

        Task {
            defer { loadingFontKeys.remove(key) }

            do {
                let entries = try await FontsourceCatalog.resolveFontFiles(
                    family: family,
                    weights: [previewWeight(for: family)]
                )
                guard let entry = entries.first else { return }
                let fontName = try await downloadAndRegisterPreviewFont(
                    from: entry.fileURL,
                    cacheName: "fontsource-\(family.id)"
                )
                previewFontNames[key] = fontName
            } catch {
                // Keep the list quiet; preview loading is best-effort.
            }
        }
    }

    private func previewWeight(for family: FontFamily) -> FontWeight {
        let parsedWeights = family.variants.compactMap { variant -> Int? in
            let cleaned = variant.replacingOccurrences(of: "italic", with: "")
            if cleaned.isEmpty || cleaned == "regular" { return 400 }
            return Int(cleaned)
        }
        let weights = Set(parsedWeights)
        return FontWeight(weight: weights.contains(400) ? 400 : (weights.sorted().first ?? 400), italic: false)
    }

    private func previewWeight(for family: FontsourceFamily) -> FontWeight {
        let weights = Set(family.weights)
        return FontWeight(weight: weights.contains(400) ? 400 : (weights.sorted().first ?? 400), italic: false)
    }

    private func downloadAndRegisterPreviewFont(from url: URL, cacheName: String) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("font-file-installer-macOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let previewDir = cacheDir.appendingPathComponent("font-file-installer/previews", isDirectory: true)
        try FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)

        let ext = url.pathExtension.isEmpty ? "ttf" : url.pathExtension
        let safeName = cacheName.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let fileURL = previewDir.appendingPathComponent("\(safeName).\(ext)")
        try data.write(to: fileURL)

        guard
            let provider = CGDataProvider(url: fileURL as CFURL),
            let cgFont = CGFont(provider),
            let postScriptName = cgFont.postScriptName as String?
        else {
            throw PreviewError.invalidFont
        }

        var registrationError: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, &registrationError)
        return postScriptName
    }

    private enum PreviewError: Error {
        case invalidFont
    }
}

struct FontPreviewSample: View {
    let fontName: String?

    var body: some View {
        Text("Aa Bb Cc")
            .font(fontName.map { .custom($0, size: 18) } ?? .system(size: 18))
            .foregroundStyle(fontName == nil ? Color.secondary.opacity(0.55) : Color.primary)
            .lineLimit(1)
            .frame(width: 96, alignment: .trailing)
    }
}
