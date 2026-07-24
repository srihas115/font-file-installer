import SwiftUI

struct FontsourceView: View {
    @State private var searchText = ""
    @State private var families: [FontsourceFamily] = []
    @State private var isLoadingCatalog = false
    @State private var loadError: String?

    @State private var selectedFamily: FontsourceFamily?
    @State private var selectedFamilyIDs: Set<String> = []
    @State private var selectedWeights: Set<Int> = [400, 700]
    @State private var includeItalic = false
    @State private var forceOverwrite = false

    @State private var isInstalling = false
    @State private var installResult: InstallResult?
    @State private var installError: String?

    private var filteredFamilies: [FontsourceFamily] {
        guard !searchText.isEmpty else { return families }
        return families.filter {
            $0.family.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Search Fontsource…", text: $searchText)
                .textFieldStyle(.roundedBorder)

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
                            Text(family.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectOnlyFamily(family)
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

            if let installResult {
                InstallResultsView(result: installResult)
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
                ForEach(family.weights.sorted(), id: \.self) { weight in
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
                Button(isInstalling ? "Installing…" : installButtonTitle) {
                    installSelectedFamilies()
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
        installResult = nil
        installError = nil
    }

    private func focusFamily(_ family: FontsourceFamily) {
        selectedFamily = family
        installResult = nil
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
        installResult = nil

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

                    combinedResult.append(FontInstaller.install(from: tempDir, force: force))
                }
                let finalResult = combinedResult
                await MainActor.run {
                    installResult = finalResult
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
