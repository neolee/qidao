import SwiftUI

struct EditToolboxView: View {
    @ObservedObject var viewModel: BoardViewModel

    var body: some View {
        GroupBox(label: Label("Edit Toolbox".localized, systemImage: "pencil.and.outline")) {
            VStack(spacing: 10) {
                Text("Edit Mode Tools Placeholder")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
            .padding(5)
        }
    }
}
