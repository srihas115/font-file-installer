import SwiftUI

enum FontSortOrder: String, CaseIterable {
    case popular = "Most Popular"
    case alphabetical = "Alphabetical"
}

struct GoogleFontsView: View {
    @StateObject private var previewStore = FontPreviewStore()

    @State private var searchText = ""
    @AppStorage(AppSettings.defaultSortOrderKey) private var sortOrder = FontSortOrder.alphabetical.rawValue
    @State private var families: [FontFamily] = []
    @State private var installedFamilyNames: Set<String> = []
    @State private var isLoadingCatalog = false
    @State private var loadError: String?

    @State private var selectedFamily: FontFamily?
    @State private var selectedFamilyIDs: Set<String> = []
    @State private var selectedWeights: Set<Int> = [400, 700]
    @State private var includeItalic = false
    @State private var forceOverwrite = false

    @State private var isInstalling = false
    @State private var installError: String?

    private let providerURL = URL(string: "https://fonts.google.com/")!

    private var filteredFamilies: [FontFamily] {
        let base = searchText.isEmpty
            ? families
            : families.filter { $0.family.localizedCaseInsensitiveContains(searchText) }
        return sorted(base.filter { !isInstalled($0.family) })
    }

    private func sorted(_ families: [FontFamily]) -> [FontFamily] {
        switch FontSortOrder(rawValue: sortOrder) ?? .popular {
        case .alphabetical:
            return families.sorted { $0.family < $1.family }
        case .popular:
            let rank = GoogleFontsCatalog.bundledPopularityRank()
            return families.sorted {
                (rank[$0.family] ?? Int.max, $0.family) < (rank[$1.family] ?? Int.max, $1.family)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Search Google Fonts…", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Picker("", selection: $sortOrder) {
                    ForEach(FontSortOrder.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)
            }
            ConfirmingTextLink(title: "Fonts by Google Fonts", url: providerURL)
                .font(.caption)

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
                    HStack(spacing: 8) {
                        Button {
                            toggleFamilySelection(family)
                        } label: {
                            Image(systemName: selectedFamilyIDs.contains(family.id) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 15))
                                .foregroundStyle(selectedFamilyIDs.contains(family.id) ? Color.accentColor : Color.secondary)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help(selectedFamilyIDs.contains(family.id) ? "Deselect" : "Select")

                        HStack {
                            Text(family.family)
                            Spacer()
                            FontPreviewSample(fontName: previewStore.fontName(for: .google(family.id)))
                        }
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectOnlyFamily(family)
                        }
                        .task(id: family.id) {
                            previewStore.loadGooglePreview(for: family)
                        }
                    }
                    .listRowBackground(selectedFamilyIDs.contains(family.id) ? Color.accentColor.opacity(0.15) : Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120, maxHeight: .infinity)
            }

            if let selectedFamily {
                familyDetail(selectedFamily)
            }

            if let installError {
                Text(installError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await loadCatalog(forceRefresh: false)
            refreshInstalledFamilies()
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
                Toggle("All", isOn: allWeightsBinding(availableWeights))
                    .toggleStyle(.button)
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
                Button {
                    installSelectedFamilies()
                } label: {
                    LoadingButtonLabel(
                        title: isInstalling ? "Installing…" : installButtonTitle,
                        isLoading: isInstalling
                    )
                }
                .disabled(isInstalling || selectedFamilyIDs.isEmpty || selectedWeights.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var installButtonTitle: String {
        selectedFamilyIDs.count > 1 ? "Install Selected" : "Install"
    }

    private func selectOnlyFamily(_ family: FontFamily) {
        selectedFamilyIDs = [family.id]
        focusFamily(family)
    }

    private func toggleFamilySelection(_ family: FontFamily) {
        if selectedFamilyIDs.contains(family.id) {
            selectedFamilyIDs.remove(family.id)
            if selectedFamily?.id == family.id {
                selectedFamily = families.first { selectedFamilyIDs.contains($0.id) }
                if let selectedFamily {
                    setDefaultWeights(for: selectedFamily)
                }
            }
        } else {
            selectedFamilyIDs.insert(family.id)
            focusFamily(family)
        }
        installError = nil
    }

    private func focusFamily(_ family: FontFamily) {
        selectedFamily = family
        installError = nil
        setDefaultWeights(for: family)
        includeItalic = false
    }

    private func setDefaultWeights(for family: FontFamily) {
        let available = Set(weights(for: family))
        selectedWeights = available.contains(400) || available.contains(700)
            ? available.intersection([400, 700])
            : Set(available.prefix(1))
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

    private func allWeightsBinding(_ weights: [Int]) -> Binding<Bool> {
        Binding(
            get: { Set(weights).isSubset(of: selectedWeights) },
            set: { isOn in
                if isOn {
                    selectedWeights.formUnion(weights)
                } else {
                    selectedWeights.removeAll()
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

    private func refreshInstalledFamilies() {
        DispatchQueue.global(qos: .userInitiated).async {
            let installed = InstalledFontLookup.installedFamilyNames()
            DispatchQueue.main.async {
                installedFamilyNames = installed
                selectedFamilyIDs = selectedFamilyIDs.filter { id in
                    !installed.contains(InstalledFontLookup.normalizedFamilyName(id))
                }
                if let selectedFamily, installed.contains(InstalledFontLookup.normalizedFamilyName(selectedFamily.family)) {
                    self.selectedFamily = nil
                }
            }
        }
    }

    private func isInstalled(_ familyName: String) -> Bool {
        installedFamilyNames.contains(InstalledFontLookup.normalizedFamilyName(familyName))
    }

    private func installSelectedFamilies() {
        let selectedFamilies = families.filter { selectedFamilyIDs.contains($0.id) }
        guard !selectedFamilies.isEmpty else { return }

        isInstalling = true
        installError = nil

        let force = forceOverwrite
        let requestedWeights = selectedWeights
        let shouldIncludeItalic = includeItalic

        // Detached so the network calls and the synchronous file-copy work in
        // FontInstaller.install run off the main actor, matching how
        // ContentView.runInstall() offloads the same call to a background queue.
        Task.detached {
            var combinedResult = InstallResult()
            do {
                for family in selectedFamilies {
                    let weights = googleWeightsToInstall(
                        for: family,
                        selectedWeights: requestedWeights,
                        includeItalic: shouldIncludeItalic
                    )
                    let entries = try await GoogleFontsCatalog.resolveFontFiles(family: family.family, weights: weights)
                    guard !entries.isEmpty else {
                        throw GoogleFontsCatalog.CatalogError.invalidResponse
                    }
                    let tempDir = try await GoogleFontsCatalog.downloadFonts(entries, family: family.family)
                    defer { try? FileManager.default.removeItem(at: tempDir) }

                    let outcome = FontInstaller.install(from: tempDir, force: force)
                    InstalledFontRegistry.record(outcome, source: "Google Fonts · \(family.family)")
                    combinedResult.append(outcome)
                }

                let finalResult = combinedResult
                await MainActor.run {
                    isInstalling = false
                    refreshInstalledFamilies()
                    InstallNotifier.notify(result: finalResult)
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

private func googleWeightsToInstall(
    for family: FontFamily,
    selectedWeights: Set<Int>,
    includeItalic: Bool
) -> [FontWeight] {
    let variants = family.variants
    let availableWeights = Set(variants.compactMap { variant -> Int? in
        let cleaned = variant.replacingOccurrences(of: "italic", with: "")
        if cleaned.isEmpty || cleaned == "regular" { return 400 }
        return Int(cleaned)
    })
    let usableWeights = selectedWeights.intersection(availableWeights)
    let resolvedWeights = usableWeights.isEmpty
        ? Set([availableWeights.contains(400) ? 400 : (availableWeights.sorted().first ?? 400)])
        : usableWeights
    let hasItalic = variants.contains { $0.contains("italic") }

    return resolvedWeights.map { FontWeight(weight: $0, italic: false) }
        + (includeItalic && hasItalic ? resolvedWeights.map { FontWeight(weight: $0, italic: true) } : [])
}
