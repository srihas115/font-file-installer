import AppKit
import SwiftUI

struct ConfirmingTextLink: View {
    let title: String
    let url: URL

    @State private var isHovered = false
    @State private var isShowingConfirmation = false

    var body: some View {
        Button {
            isShowingConfirmation = true
        } label: {
            Text(title)
                .foregroundStyle(.blue)
                .underline(isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .help(url.absoluteString)
        .alert("Open Link?", isPresented: $isShowingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Open") {
                NSWorkspace.shared.open(url)
            }
        } message: {
            Text("This will take you to \(url.absoluteString). Are you sure?")
        }
    }
}

enum ExternalLinkParser {
    static func url(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }
}
