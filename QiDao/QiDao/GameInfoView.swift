import SwiftUI

struct GameInfoView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Binding var showInfoEditor: Bool
    @ObservedObject private var langManager = LanguageManager.shared

    var body: some View {
        GroupBox(label: Label("Game Info".localized, systemImage: "info.circle")) {
            VStack(alignment: .leading, spacing: 8) {
                if !viewModel.metadata.gameName.isEmpty {
                    Text(viewModel.metadata.gameName)
                        .font(.headline)
                        .padding(.bottom, 4)
                }
                if !viewModel.metadata.event.isEmpty {
                    InfoRow(label: "Event".localized, value: viewModel.metadata.event)
                }
                if !viewModel.metadata.date.isEmpty {
                    InfoRow(label: "Date".localized, value: viewModel.metadata.date)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        Text("Black".localized).font(.caption).foregroundColor(.secondary)
                        Text(viewModel.metadata.blackName.isEmpty ? "Black".localized : viewModel.metadata.blackName)
                            .fontWeight(.bold)
                            .lineLimit(1)
                        if !viewModel.metadata.blackRank.isEmpty {
                            Text(viewModel.metadata.blackRank).font(.caption)
                        }
                    }
                    Spacer()
                    Text("vs".localized).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("White".localized).font(.caption).foregroundColor(.secondary)
                        Text(viewModel.metadata.whiteName.isEmpty ? "White".localized : viewModel.metadata.whiteName)
                            .fontWeight(.bold)
                            .lineLimit(1)
                        if !viewModel.metadata.whiteRank.isEmpty {
                            Text(viewModel.metadata.whiteRank).font(.caption)
                        }
                    }
                }

                Divider()

                InfoRow(label: "Komi".localized, value: String(format: "%.1f", viewModel.metadata.komi))
                if !viewModel.metadata.result.isEmpty {
                    InfoRow(label: "Result".localized, value: viewModel.formattedResult)
                }

                Text("\("Next".localized): \(viewModel.nextColor == .black ? "Black".localized : "White".localized)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .padding(.top, 4)

                Button(action: { showInfoEditor = true }) {
                    Label("Edit".localized, systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.top, 5)
                .focusable(false)
            }
            .padding(5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
    }
}
