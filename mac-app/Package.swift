// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "InstallFonts",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "InstallFonts",
            path: "Sources/InstallFonts"
        )
    ]
)
