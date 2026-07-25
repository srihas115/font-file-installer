import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
