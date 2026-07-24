import SwiftUI

struct GoogleFontsView: View {
    @State private var searchText = ""
    @State private var families: [FontFamily] = []
    @State private var isLoadingCatalog = false
    @State private var loadError: String?

    @State private var selectedFamily: FontFamily?
    @State private var selectedWeights: Set<Int> = [400, 700]
    @State private var includeItalic = false
    @State private var forceOverwrite = false

    @State private var isInstalling = false
    @State private var installResult: InstallResult?
    @State private var installError: String?

    private var filteredFamilies: [FontFamily] {
        guard !searchText.isEmpty else { return families }
        return families.filter { $0.family.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search Google Fonts…", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if isLoadingCatalog {
                ProgressView("Loading font catalog…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else if let loadError {
                VStack(spacing: 8) {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadCatalog(forceRefresh: false) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
            } else {
                List(filteredFamilies) { family in
                    HStack {
                        Text(family.family)
                        Spacer()
                        Text(family.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .background(family == selectedFamily ? Color.accentColor.opacity(0.15) : Color.clear)
                    .onTapGesture {
                        selectFamily(family)
                    }
                }
                .frame(minHeight: 200, maxHeight: 260)
            }

            if let selectedFamily {
                familyDetail(selectedFamily)
            }

            if let installError {
                Text(installError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if let installResult {
                InstallResultsView(result: installResult)
            }
        }
        .task {
            await loadCatalog(forceRefresh: false)
        }
    }

    private func familyDetail(_ family: FontFamily) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(family.family)
                .font(.headline)

            let availableWeights = weights(for: family)
            let hasItalic = family.variants.contains { $0.contains("italic") }

            HStack {
                ForEach(availableWeights, id: \.self) { weight in
                    Toggle("\(weight)", isOn: weightBinding(weight))
                        .toggleStyle(.button)
                }
                if hasItalic {
                    Toggle("Italic", isOn: $includeItalic)
                        .toggleStyle(.button)
                }
            }

            HStack {
                Toggle("Overwrite existing fonts", isOn: $forceOverwrite)
                Spacer()
                Button(isInstalling ? "Installing…" : "Install") {
                    install(family)
                }
                .disabled(isInstalling || selectedWeights.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func selectFamily(_ family: FontFamily) {
        selectedFamily = family
        installResult = nil
        installError = nil
        let available = Set(weights(for: family))
        selectedWeights = available.contains(400) || available.contains(700)
            ? available.intersection([400, 700])
            : Set(available.prefix(1))
        includeItalic = false
    }

    private func weights(for family: FontFamily) -> [Int] {
        // Variants look like "regular", "italic", "700", "700italic", etc. — Google
        // Fonts uses the bare words "regular"/"italic" for weight 400, not "400".
        let parsed = family.variants.compactMap { variant -> Int? in
            let cleaned = variant.replacingOccurrences(of: "italic", with: "")
            if cleaned.isEmpty || cleaned == "regular" { return 400 }
            return Int(cleaned)
        }
        let distinct = Array(Set(parsed)).sorted()
        return distinct.isEmpty ? [400] : distinct
    }

    private func weightBinding(_ weight: Int) -> Binding<Bool> {
        Binding(
            get: { selectedWeights.contains(weight) },
            set: { isOn in
                if isOn {
                    selectedWeights.insert(weight)
                } else {
                    selectedWeights.remove(weight)
                }
            }
        )
    }

    private func loadCatalog(forceRefresh: Bool) async {
        isLoadingCatalog = true
        loadError = nil
        do {
            families = try await GoogleFontsCatalog.loadCatalog(forceRefresh: forceRefresh)
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingCatalog = false
    }

    private func install(_ family: FontFamily) {
        isInstalling = true
        installError = nil
        installResult = nil

        let weights = selectedWeights.map { FontWeight(weight: $0, italic: false) }
            + (includeItalic ? selectedWeights.map { FontWeight(weight: $0, italic: true) } : [])
        let force = forceOverwrite

        // Detached so the network calls and the synchronous file-copy work in
        // FontInstaller.install run off the main actor, matching how
        // ContentView.runInstall() offloads the same call to a background queue.
        Task.detached {
            do {
                let entries = try await GoogleFontsCatalog.resolveFontFiles(family: family.family, weights: weights)
                guard !entries.isEmpty else {
                    throw GoogleFontsCatalog.CatalogError.invalidResponse
                }
                let tempDir = try await GoogleFontsCatalog.downloadFonts(entries, family: family.family)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let outcome = FontInstaller.install(from: tempDir, force: force)
                await MainActor.run {
                    installResult = outcome
                    isInstalling = false
                }
            } catch {
                await MainActor.run {
                    installError = error.localizedDescription
                    isInstalling = false
                }
            }
        }
    }
}
