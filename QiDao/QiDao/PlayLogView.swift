import SwiftUI

struct PlayLogView: View {
    @ObservedObject var viewModel: BoardViewModel

    var body: some View {
        GroupBox(label: Label("Play Log".localized, systemImage: "list.bullet.rectangle")) {
            VStack(spacing: 10) {
                Text("Play Mode Log Placeholder")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
            .padding(5)
        }
    }
}
