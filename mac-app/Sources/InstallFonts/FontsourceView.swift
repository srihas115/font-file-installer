import SwiftUI

struct FontsourceView: View {
    @State private var searchText = ""
    @State private var families: [FontsourceFamily] = []
    @State private var isLoadingCatalog = false
    @State private var loadError: String?

    @State private var selectedFamily: FontsourceFamily?
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
        VStack(alignment: .leading, spacing: 12) {
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
                Button(isInstalling ? "Installing…" : "Install") {
                    install(family)
                }
                .disabled(isInstalling || selectedWeights.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func selectFamily(_ family: FontsourceFamily) {
        selectedFamily = family
        installResult = nil
        installError = nil
        let available = Set(family.weights)
        selectedWeights = available.contains(400) || available.contains(700)
            ? available.intersection([400, 700])
            : Set(available.prefix(1))
        includeItalic = false
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

    private func install(_ family: FontsourceFamily) {
        isInstalling = true
        installError = nil
        installResult = nil

        let weights = selectedWeights.map { FontWeight(weight: $0, italic: false) }
            + (includeItalic ? selectedWeights.map { FontWeight(weight: $0, italic: true) } : [])
        let force = forceOverwrite

        Task.detached {
            do {
                let entries = try await FontsourceCatalog.resolveFontFiles(family: family, weights: weights)
                let tempDir = try await FontsourceCatalog.downloadFonts(entries, family: family.family)
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
