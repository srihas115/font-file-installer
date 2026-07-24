import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum InstallMode: String, CaseIterable {
    case folder = "From Folder/Zip"
    case google = "Google Fonts"
    case fontsource = "Fontsource"
}

struct ContentView: View {
    @EnvironmentObject private var updateController: UpdateCheckController

    @State private var mode: InstallMode = .folder
    @State private var selectedFolder: URL?
    @State private var isTargeted = false
    @State private var isDropZoneHovered = false
    @State private var forceOverwrite = false
    @State private var isInstalling = false
    @State private var result: InstallResult?
    @State private var errorMessage: String?
    @State private var didAutoExpandForCatalog = false
    @State private var didSetInitialWindowHeight = false

    var body: some View {
        VStack(spacing: 8) {
            Text("Font Installer")
                .font(.title2)
                .bold()

            Picker("", selection: $mode) {
                ForEach(InstallMode.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                if mode == .google {
                    GoogleFontsView()
                } else if mode == .fontsource {
                    FontsourceView()
                } else {
                    folderInstallView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(20)
        .alert(updateController.alertTitle, isPresented: $updateController.isShowingAlert) {
            if let releaseURL = updateController.releaseURL {
                Button("Open Releases") {
                    NSWorkspace.shared.open(releaseURL)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(updateController.alertMessage)
        }
        .onChange(of: mode) { newMode in
            adjustWindowHeight(for: newMode)
        }
        .onAppear {
            resetInitialFolderWindowHeight()
        }
    }

    private var folderInstallView: some View {
        VStack(spacing: 16) {
            dropZone

            VStack(spacing: 16) {
                HStack {
                    Button("Choose Folder or Zip…") {
                        chooseFolder()
                    }
                    Toggle("Overwrite existing fonts", isOn: $forceOverwrite)
                    Spacer()
                    Button(updateController.isChecking ? "Checking…" : "Check for updates") {
                        updateController.checkForUpdates()
                    }
                    .disabled(updateController.isChecking)
                    .help("Check for updates")
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let result {
                    InstallResultsView(result: result)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(dropZoneFillColor)
            )
            .frame(minHeight: 120, maxHeight: .infinity)
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
                        Text("Click to choose, or drag a folder or .zip file here")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            )
            .onHover { hovering in
                isDropZoneHovered = hovering
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                chooseFolder()
            }
            .help("Choose a folder or .zip file")
    }

    private var dropZoneFillColor: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.08)
        }
        if isDropZoneHovered {
            return Color.secondary.opacity(0.12)
        }
        return Color.clear
    }

    private func adjustWindowHeight(for mode: InstallMode) {
        let compactHeight: CGFloat = 280
        let catalogHeight: CGFloat = 430

        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow else { return }

            switch mode {
            case .google, .fontsource:
                if window.frame.height < catalogHeight {
                    resize(window, toHeight: catalogHeight)
                }
                didAutoExpandForCatalog = window.frame.height <= catalogHeight + 8

            case .folder:
                guard didAutoExpandForCatalog || window.frame.height <= catalogHeight + 8 else { return }
                resize(window, toHeight: compactHeight)
                didAutoExpandForCatalog = false
            }
        }
    }

    private func resetInitialFolderWindowHeight() {
        let compactHeight: CGFloat = 280

        DispatchQueue.main.async {
            guard !didSetInitialWindowHeight, mode == .folder, let window = NSApp.keyWindow else { return }
            resize(window, toHeight: compactHeight)
            didSetInitialWindowHeight = true
            didAutoExpandForCatalog = false
        }
    }

    private func resize(_ window: NSWindow, toHeight height: CGFloat) {
        var frame = window.frame
        let maxY = frame.maxY
        frame.size.height = height
        frame.origin.y = maxY - height
        window.setFrame(frame, display: true, animate: true)
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
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

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
