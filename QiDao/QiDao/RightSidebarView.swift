import SwiftUI

struct RightSidebarView: View {
    @ObservedObject var viewModel: BoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label("Variation Tree".localized, systemImage: "arrow.triangle.branch")) {
                VariationTreeView(viewModel: viewModel)
                    .frame(maxHeight: .infinity)
            }

            GroupBox(label: Label("Move Evaluation".localized, systemImage: "list.bullet.rectangle")) {
                Text("Analysis Table Placeholder")
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.05))
            }

            GroupBox(label: Label("Evaluation".localized, systemImage: "eye")) {
                ZStack {
                    Color.black.opacity(0.05)
                    Text("Small Board Placeholder")
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .frame(minWidth: 200, maxWidth: 300)
    }
}
