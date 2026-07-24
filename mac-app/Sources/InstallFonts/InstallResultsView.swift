import SwiftUI

/// Shared installed/skipped/failed summary list, used by both the folder/zip flow
/// (`ContentView`) and the Google Fonts flow (`GoogleFontsView`).
struct InstallResultsView: View {
    let result: InstallResult

    var body: some View {
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
}
