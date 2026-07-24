import SwiftUI
import UniformTypeIdentifiers

enum InstallMode: String, CaseIterable {
    case folder = "From Folder/Zip"
    case google = "Google Fonts"
}

struct ContentView: View {
    @State private var mode: InstallMode = .folder
    @State private var selectedFolder: URL?
    @State private var isTargeted = false
    @State private var forceOverwrite = false
    @State private var isInstalling = false
    @State private var result: InstallResult?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Install Fonts")
                .font(.title2)
                .bold()

            Picker("", selection: $mode) {
                ForEach(InstallMode.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .google {
                GoogleFontsView()
            } else {
                folderInstallView
            }

            Spacer()
        }
        .padding(20)
    }

    private var folderInstallView: some View {
        VStack(spacing: 16) {
            dropZone

            HStack {
                Button("Choose Folder or Zip…") {
                    chooseFolder()
                }
                Toggle("Overwrite existing fonts", isOn: $forceOverwrite)
                Spacer()
                Button(isInstalling ? "Installing…" : "Install") {
                    runInstall()
                }
                .disabled(selectedFolder == nil || isInstalling)
                .keyboardShortcut(.defaultAction)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if let result {
                InstallResultsView(result: result)
            }
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .frame(height: 140)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    if let selectedFolder {
                        Text(selectedFolder.path)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Drag a folder or .zip file here")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            )
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let directURL = item as? URL {
                url = directURL
            }

            guard let url else { return }

            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let isZip = url.pathExtension.lowercased() == "zip"

            DispatchQueue.main.async {
                if exists && (isDirectory.boolValue || isZip) {
                    self.selectedFolder = url
                    self.errorMessage = nil
                    self.result = nil
                } else {
                    self.errorMessage = "Please drop a folder or a .zip file."
                }
            }
        }
        return true
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            selectedFolder = url
            errorMessage = nil
            result = nil
        }
    }

    private func runInstall() {
        guard let selectedFolder else { return }
        isInstalling = true
        errorMessage = nil

        let force = forceOverwrite
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = FontInstaller.install(from: selectedFolder, force: force)
            DispatchQueue.main.async {
                self.result = outcome
                self.isInstalling = false
                if outcome.found.isEmpty {
                    self.errorMessage = "No font files (.otf, .ttf, .woff, .woff2) found in that folder."
                }
            }
        }
    }
}
