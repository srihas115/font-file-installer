import SwiftUI

struct FontsourceView: View {
    @StateObject private var previewStore = FontPreviewStore()

    @State private var searchText = ""
    @AppStorage(AppSettings.defaultSortOrderKey) private var sortOrder = FontSortOrder.popular.rawValue
    @State private var families: [FontsourceFamily] = []
    @State private var isLoadingCatalog = false
    @State private var loadError: String?

    @State private var selectedFamily: FontsourceFamily?
    @State private var selectedFamilyIDs: Set<String> = []
    @State private var selectedWeights: Set<Int> = [400, 700]
    @State private var includeItalic = false
    @State private var forceOverwrite = false

    @State private var isInstalling = false
    @State private var installError: String?

    private let providerURL = URL(string: "https://fontsource.org/")!

    private let popularFamilyIDs = [
        "roboto",
        "open-sans",
        "inter",
        "noto-sans",
        "lato",
        "montserrat",
        "poppins",
        "roboto-condensed",
        "source-sans-3",
        "oswald",
        "raleway",
        "merriweather",
        "noto-serif",
        "ubuntu",
        "playfair-display",
        "nunito",
        "rubik",
    ]

    private var filteredFamilies: [FontsourceFamily] {
        let base = searchText.isEmpty
            ? families
            : families.filter {
                $0.family.localizedCaseInsensitiveContains(searchText)
                    || $0.id.localizedCaseInsensitiveContains(searchText)
            }
        return sorted(base)
    }

    private func sorted(_ families: [FontsourceFamily]) -> [FontsourceFamily] {
        switch FontSortOrder(rawValue: sortOrder) ?? .popular {
        case .alphabetical:
            return families.sorted { $0.family < $1.family }
        case .popular:
            let rank = Dictionary(uniqueKeysWithValues: popularFamilyIDs.enumerated().map { ($0.element, $0.offset) })
            return families.sorted {
                (rank[$0.id] ?? Int.max, $0.family) < (rank[$1.id] ?? Int.max, $1.family)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Search Fontsource…", text: $searchText)
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
            ConfirmingTextLink(title: "Fonts by Fontsource", url: providerURL)
                .font(.caption)

            if isLoadingCatalog {
                ProgressView("Loading Fontsource catalog…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else if let loadError {
                VStack(spacing: 8) {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadCatalog() }
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
                            FontPreviewSample(fontName: previewStore.fontName(for: .fontsource(family.id)))
                        }
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectOnlyFamily(family)
                        }
                        .task(id: family.id) {
                            previewStore.loadFontsourcePreview(for: family)
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
            await loadCatalog()
        }
    }

    private func familyDetail(_ family: FontsourceFamily) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(family.family)
                .font(.headline)

            HStack {
                let availableWeights = family.weights.sorted()
                Toggle("All", isOn: allWeightsBinding(availableWeights))
                    .toggleStyle(.button)
                ForEach(availableWeights, id: \.self) { weight in
                    Toggle("\(weight)", isOn: weightBinding(weight))
                        .toggleStyle(.button)
                }
                if family.styles.contains("italic") {
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

    private func selectOnlyFamily(_ family: FontsourceFamily) {
        selectedFamilyIDs = [family.id]
        focusFamily(family)
    }

    private func toggleFamilySelection(_ family: FontsourceFamily) {
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

    private func focusFamily(_ family: FontsourceFamily) {
        selectedFamily = family
        installError = nil
        setDefaultWeights(for: family)
        includeItalic = false
    }

    private func setDefaultWeights(for family: FontsourceFamily) {
        let available = Set(family.weights)
        selectedWeights = available.contains(400) || available.contains(700)
            ? available.intersection([400, 700])
            : Set(available.prefix(1))
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

    private func loadCatalog() async {
        isLoadingCatalog = true
        loadError = nil
        do {
            families = try await FontsourceCatalog.loadCatalog()
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingCatalog = false
    }

    private func installSelectedFamilies() {
        let selectedFamilies = families.filter { selectedFamilyIDs.contains($0.id) }
        guard !selectedFamilies.isEmpty else { return }

        isInstalling = true
        installError = nil

        let force = forceOverwrite
        let requestedWeights = selectedWeights
        let shouldIncludeItalic = includeItalic

        Task.detached {
            var combinedResult = InstallResult()
            do {
                for family in selectedFamilies {
                    let weights = fontsourceWeightsToInstall(
                        for: family,
                        selectedWeights: requestedWeights,
                        includeItalic: shouldIncludeItalic
                    )
                    let entries = try await FontsourceCatalog.resolveFontFiles(family: family, weights: weights)
                    let tempDir = try await FontsourceCatalog.downloadFonts(entries, family: family.family)
                    defer { try? FileManager.default.removeItem(at: tempDir) }

                    let outcome = FontInstaller.install(from: tempDir, force: force)
                    InstalledFontRegistry.record(outcome, source: "Fontsource · \(family.family)")
                    combinedResult.append(outcome)
                }
                let finalResult = combinedResult
                await MainActor.run {
                    isInstalling = false
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

private func fontsourceWeightsToInstall(
    for family: FontsourceFamily,
    selectedWeights: Set<Int>,
    includeItalic: Bool
) -> [FontWeight] {
    let availableWeights = Set(family.weights)
    let usableWeights = selectedWeights.intersection(availableWeights)
    let resolvedWeights = usableWeights.isEmpty
        ? Set([availableWeights.contains(400) ? 400 : (availableWeights.sorted().first ?? 400)])
        : usableWeights
    let hasItalic = family.styles.contains("italic")

    return resolvedWeights.map { FontWeight(weight: $0, italic: false) }
        + (includeItalic && hasItalic ? resolvedWeights.map { FontWeight(weight: $0, italic: true) } : [])
}
