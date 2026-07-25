import AppKit
import SwiftUI

struct AboutView: View {
    private let repoURL = URL(string: "https://github.com/srihas115/font-file-installer")!
    private let linkedInURL = URL(string: "https://www.linkedin.com/in/srihas115/")!
    private let sponsorURL = URL(string: "https://github.com/sponsors/srihas115")!
    private let coffeeURL = URL(string: "https://buymeacoffee.com/srihas")!

    @State private var hoveredIcon: String?
    @State private var pendingURL: URL?
    @State private var isShowingLinkConfirmation = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            VStack(spacing: 4) {
                Text("Font Installer")
                    .font(.headline)
                    .bold()
                Text(appVersion)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    iconButton(label: "GitHub Repo", imageName: "GitHub_Invertocat_Black", url: repoURL)
                    iconButton(label: "LinkedIn", imageName: "linkedin-svgrepo-com", url: linkedInURL)
                    iconButton(label: "GitHub Sponsors", imageName: "donate-heart-svgrepo-com", url: sponsorURL)
                    iconButton(label: "Buy Me a Coffee", imageName: "bmc-logo", url: coffeeURL)
                }
                .padding(.top, 4)
            }

            Text("Made by Srihas")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(width: 300, height: 206)
        .alert("Open Link?", isPresented: $isShowingLinkConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Open") {
                if let pendingURL {
                    NSWorkspace.shared.open(pendingURL)
                }
                pendingURL = nil
            }
        } message: {
            Text("This will take you to \(pendingURL?.absoluteString ?? "that link"). Are you sure?")
        }
    }

    private func iconButton(
        label: String,
        imageName: String,
        url: URL,
    ) -> some View {
        let isHovered = hoveredIcon == label

        return Button {
            pendingURL = url
            isShowingLinkConfirmation = true
        } label: {
            if let image = socialImage(named: imageName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .saturation(isHovered ? 1 : 0)
                    .opacity(isHovered ? 1 : 0.55)
                    .scaleEffect(isHovered ? 1.16 : 1)
                    .animation(.easeOut(duration: 0.12), value: isHovered)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .onHover { hovering in
            hoveredIcon = hovering ? label : nil
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .help(label)
        .accessibilityLabel(label)
    }

    private func socialImage(named name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "svg") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: name)
    }
}
