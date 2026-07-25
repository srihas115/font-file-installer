import SwiftUI

private struct InstalledFontItem: Identifiable, Hashable {
    let url: URL
    let fileName: String
    let familyName: String
    let styleLabel: String
    let source: String
    let designer: String?
    let license: String?
    let installedAt: Date?
    let fileSize: Int64

    var id: String { fileName }
}

private struct InstalledFontGroup: Identifiable {
    let familyName: String
    let source: String
    let designer: String?
    let license: String?
    let installedAt: Date?
    let totalSize: Int64
    let items: [InstalledFontItem]

    var id: String { "\(familyName)-\(source)" }
}

struct InstalledFontsView: View {
    @AppStorage(AppSettings.installedFontsSortOrderKey) private var sortOrder = InstalledFontsSortOrder.recentlyInstalled.rawValue

    @State private var groups: [InstalledFontGroup] = []
    @State private var selectedFileNames: Set<String> = []
    @State private var statusMessage: String?
    @State private var showingUninstallConfirmation = false
    @State private var isRefreshing = false
    @State private var infoPopoverGroupID: String?
    @State private var isFontsPathHovered = false

    private var allFileNames: Set<String> {
        Set(groups.flatMap(\.items).map(\.fileName))
    }

    private var selectedCount: Int {
        selectedFileNames.count
    }

    private var allSelectionIconName: String {
        if selectedFileNames.isEmpty { return "square" }
        if selectedFileNames.isSuperset(of: allFileNames) { return "checkmark.square.fill" }
        return "minus.square.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Installed Fonts")
                        .font(.headline)
                    Button {
                        NSWorkspace.shared.open(FontInstaller.userFontsDirectory)
                    } label: {
                        Text(FontInstaller.userFontsDirectory.path)
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .underline(isFontsPathHovered)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isFontsPathHovered = hovering
                        if hovering {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    .help("Open Fonts folder in Finder")
                }
                Spacer()
                Button {
                    refreshInstalledFonts(clearStatus: true)
                } label: {
                    LoadingButtonLabel(
                        title: isRefreshing ? "Refreshing…" : "Refresh",
                        isLoading: isRefreshing
                    )
                }
                .disabled(isRefreshing)
                Button("Uninstall Selected") {
                    showingUninstallConfirmation = true
                }
                .disabled(selectedFileNames.isEmpty)
            }

            if groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "textformat")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No Fonts Found")
                        .font(.headline)
                    Text("Fonts installed in your user font folder will appear here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(groups) { group in
                    Section {
                        ForEach(group.items) { item in
                            HStack(spacing: 8) {
                                Spacer()
                                    .frame(width: 28)

                                Button {
                                    toggle(item)
                                } label: {
                                    Image(systemName: selectedFileNames.contains(item.fileName) ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 15))
                                        .foregroundStyle(selectedFileNames.contains(item.fileName) ? Color.accentColor : Color.secondary)
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.styleLabel)
                                    Text(item.fileName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.leading, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggle(item)
                            }
                        }
                    } header: {
                        HStack(alignment: .top, spacing: 8) {
                            Button {
                                toggle(group)
                            } label: {
                                Image(systemName: selectionIconName(for: group))
                                    .font(.system(size: 15))
                                    .foregroundStyle(isGroupSelected(group) ? Color.accentColor : Color.secondary)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)

                            Text(group.familyName)
                                .font(.headline)
                                .textCase(nil)
                                .lineLimit(1)

                            Spacer()

                            Button {
                                infoPopoverGroupID = group.id
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(metadataHelp(for: group))
                            .popover(isPresented: Binding(
                                get: { infoPopoverGroupID == group.id },
                                set: { isPresented in
                                    if !isPresented {
                                        infoPopoverGroupID = nil
                                    }
                                }
                            )) {
                                FontMetadataPopover(group: group)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 36))
                }
                .listStyle(.plain)
                .padding(.trailing, -12)
            }

            HStack(spacing: 8) {
                if !groups.isEmpty {
                    Button {
                        toggleAll()
                    } label: {
                        Image(systemName: allSelectionIconName)
                            .font(.system(size: 15))
                            .foregroundStyle(selectedFileNames.isEmpty ? Color.secondary : Color.accentColor)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)

                    Text("Select all")
                        .font(.callout)
                        .onTapGesture {
                            toggleAll()
                        }
                }

                Text("\(selectedCount) font\(selectedCount == 1 ? "" : "s") selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Uninstall Selected") {
                    showingUninstallConfirmation = true
                }
                .disabled(selectedFileNames.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshInstalledFonts(clearStatus: true)
        }
        .onChange(of: sortOrder) { _ in
            refreshInstalledFonts(clearStatus: true)
        }
        .alert("Are you sure you want to uninstall \(selectedCount) font\(selectedCount == 1 ? "" : "s")?", isPresented: $showingUninstallConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                uninstallSelected()
            }
        } message: {
            Text("This will remove the selected font file\(selectedCount == 1 ? "" : "s") from your user Fonts folder.")
        }
    }

    private func refreshInstalledFonts(clearStatus: Bool) {
        guard !isRefreshing else { return }
        isRefreshing = true
        let selectedSortOrder = InstalledFontsSortOrder(rawValue: sortOrder) ?? .recentlyInstalled

        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = loadInstalledFonts(sortOrder: selectedSortOrder)
            DispatchQueue.main.async {
                groups = loaded.groups
                selectedFileNames.formIntersection(loaded.fileNames)
                if clearStatus {
                    statusMessage = nil
                }
                isRefreshing = false
            }
        }
    }

    private func loadInstalledFonts(sortOrder: InstalledFontsSortOrder) -> (groups: [InstalledFontGroup], fileNames: Set<String>) {
        let records = InstalledFontRegistry.records()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: FontInstaller.userFontsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let items = urls
            .filter { FontInstaller.fontExtensions.contains($0.pathExtension.lowercased()) }
            .map { url -> InstalledFontItem in
                let fileName = url.lastPathComponent
                let parsed = parseFontFileName(fileName)
                let metadata = FontMetadataReader.metadata(for: url)
                let record = records[fileName]
                return InstalledFontItem(
                    url: url,
                    fileName: fileName,
                    familyName: metadata.familyName ?? parsed.family,
                    styleLabel: metadata.styleName ?? parsed.style,
                    source: record?.source ?? "Unknown",
                    designer: metadata.designer,
                    license: metadata.license,
                    installedAt: record?.installedAt,
                    fileSize: fileSize(for: url)
                )
            }
            .sorted { ($0.familyName, $0.styleLabel, $0.fileName) < ($1.familyName, $1.styleLabel, $1.fileName) }

        let grouped = Dictionary(grouping: items) { "\($0.familyName)\u{1F}\($0.source)" }
        let loadedGroups = grouped.values
            .map { values in
                let sortedItems = values.sorted { ($0.styleLabel, $0.fileName) < ($1.styleLabel, $1.fileName) }
                return InstalledFontGroup(
                    familyName: sortedItems.first?.familyName ?? "Unknown Font",
                    source: sortedItems.first?.source ?? "Unknown",
                    designer: firstMetadataValue(in: sortedItems, keyPath: \.designer),
                    license: firstMetadataValue(in: sortedItems, keyPath: \.license),
                    installedAt: sortedItems.compactMap(\.installedAt).max(),
                    totalSize: sortedItems.reduce(0) { $0 + $1.fileSize },
                    items: sortedItems
                )
            }
            .sorted { groupSortPrecedes($0, $1, sortOrder: sortOrder) }

        return (loadedGroups, Set(items.map(\.fileName)))
    }

    private func toggle(_ item: InstalledFontItem) {
        if selectedFileNames.contains(item.fileName) {
            selectedFileNames.remove(item.fileName)
        } else {
            selectedFileNames.insert(item.fileName)
        }
    }

    private func toggle(_ group: InstalledFontGroup) {
        let groupFileNames = Set(group.items.map(\.fileName))
        if selectedFileNames.isSuperset(of: groupFileNames) {
            selectedFileNames.subtract(groupFileNames)
        } else {
            selectedFileNames.formUnion(groupFileNames)
        }
    }

    private func toggleAll() {
        if !allFileNames.isEmpty, selectedFileNames.isSuperset(of: allFileNames) {
            selectedFileNames.removeAll()
        } else {
            selectedFileNames = allFileNames
        }
    }

    private func selectionIconName(for group: InstalledFontGroup) -> String {
        let groupFileNames = Set(group.items.map(\.fileName))
        if selectedFileNames.isSuperset(of: groupFileNames) { return "checkmark.square.fill" }
        if selectedFileNames.isDisjoint(with: groupFileNames) { return "square" }
        return "minus.square.fill"
    }

    private func isGroupSelected(_ group: InstalledFontGroup) -> Bool {
        !selectedFileNames.isDisjoint(with: Set(group.items.map(\.fileName)))
    }

    private func metadataHelp(for group: InstalledFontGroup) -> String {
        "Source: \(group.source)\nLicense: \(group.license ?? "Not available")\nInstalled: \(formattedInstallDate(group.installedAt))\nSize: \(formattedFileSize(group.totalSize))"
    }

    private func groupSortPrecedes(_ lhs: InstalledFontGroup, _ rhs: InstalledFontGroup, sortOrder: InstalledFontsSortOrder) -> Bool {
        switch sortOrder {
        case .recentlyInstalled:
            let leftDate = lhs.installedAt ?? .distantPast
            let rightDate = rhs.installedAt ?? .distantPast
            if leftDate != rightDate { return leftDate > rightDate }
            return (lhs.familyName, lhs.source) < (rhs.familyName, rhs.source)
        case .size:
            if lhs.totalSize != rhs.totalSize { return lhs.totalSize > rhs.totalSize }
            return (lhs.familyName, lhs.source) < (rhs.familyName, rhs.source)
        case .alphabetical:
            return (lhs.familyName, lhs.source) < (rhs.familyName, rhs.source)
        }
    }

    private func fileSize(for url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func formattedFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formattedInstallDate(_ date: Date?) -> String {
        guard let date else { return "Not available" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func firstMetadataValue(in items: [InstalledFontItem], keyPath: KeyPath<InstalledFontItem, String?>) -> String? {
        items.compactMap { item in
            item[keyPath: keyPath]?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .first { !$0.isEmpty }
    }

    private func uninstallSelected() {
        let selectedItems = groups.flatMap(\.items).filter { selectedFileNames.contains($0.fileName) }
        var removed: Set<String> = []
        var failures: [String] = []

        for item in selectedItems {
            do {
                try FileManager.default.removeItem(at: item.url)
                removed.insert(item.fileName)
            } catch {
                failures.append("\(item.fileName): \(error.localizedDescription)")
            }
        }

        InstalledFontRegistry.remove(fileNames: removed)
        selectedFileNames.subtract(removed)
        refreshInstalledFonts(clearStatus: false)
        statusMessage = failures.isEmpty
            ? "Uninstalled \(removed.count) font\(removed.count == 1 ? "" : "s")."
            : "Uninstalled \(removed.count). Failed \(failures.count)."
    }

    private func parseFontFileName(_ fileName: String) -> (family: String, style: String) {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        guard parts.count > 1 else {
            return (stem, "Regular")
        }

        var styleTokens: [String] = []
        var familyTokens = parts

        while let last = familyTokens.last, isStyleToken(last) {
            styleTokens.insert(last, at: 0)
            familyTokens.removeLast()
        }

        let family = familyTokens.isEmpty ? stem : familyTokens.joined(separator: " ")
        let style = styleTokens.isEmpty ? "Regular" : styleTokens.map(formatStyleToken).joined(separator: " ")
        return (family, style)
    }

    private func isStyleToken(_ token: String) -> Bool {
        Int(token) != nil || ["italic", "regular", "bold", "light", "medium", "thin", "black"].contains(token.lowercased())
    }

    private func formatStyleToken(_ token: String) -> String {
        let lower = token.lowercased()
        if Int(token) != nil { return token }
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}

private struct FontMetadataPopover: View {
    let group: InstalledFontGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.familyName)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Aa Bb Cc")
                .font(.custom(group.familyName, size: 28))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                metadataRow(label: "Source", value: group.source)
                metadataRow(label: "License", value: group.license ?? "Not available")
                metadataRow(label: "Date installed", value: formattedInstallDate(group.installedAt))
                metadataRow(label: "Total size", value: formattedFileSize(group.totalSize))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Files")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    ForEach(group.items) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.styleLabel)
                                .lineLimit(1)
                            Spacer()
                            Text(formattedFileSize(item.fileSize))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
    }

    private func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            if let url = ExternalLinkParser.url(from: value) {
                ConfirmingTextLink(title: value, url: url)
                    .font(.callout)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(value)
                    .font(.callout)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formattedInstallDate(_ date: Date?) -> String {
        guard let date else { return "Not available" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
