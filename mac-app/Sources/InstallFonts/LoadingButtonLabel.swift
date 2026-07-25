import SwiftUI

struct LoadingButtonLabel: View {
    let title: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(title)
        }
    }
}
