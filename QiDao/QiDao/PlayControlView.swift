import SwiftUI

struct PlayControlView: View {
    @ObservedObject var viewModel: BoardViewModel

    var body: some View {
        GroupBox(label: Label("Play Control".localized, systemImage: "gamecontroller")) {
            VStack(spacing: 10) {
                Text("Play Mode Controls Placeholder")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
            .padding(5)
        }
    }
}
