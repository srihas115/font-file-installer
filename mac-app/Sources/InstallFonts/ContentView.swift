import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
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
                resultsView(result)
            }

            Spacer()
        }
        .padding(20)
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

    private func resultsView(_ result: InstallResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Found \(result.found.count) · Installed \(result.installed.count) · Skipped \(result.skipped.count) · Failed \(result.failed.count)")
                .font(.callout)
                .bold()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.installed, id: \.self) { name in
                        Label(name, systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                    ForEach(result.skipped, id: \.self) { name in
                        Label("\(name) (already installed)", systemImage: "arrow.uturn.left.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    ForEach(result.failed, id: \.name) { item in
                        Label("\(item.name): \(item.reason)", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
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
