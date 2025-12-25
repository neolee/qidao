import SwiftUI
import qidao_coreFFI

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct GameInfoEditorView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Environment(\.dismiss) var dismiss
    @State private var metadata: GameMetadata

    init(viewModel: BoardViewModel) {
        self.viewModel = viewModel
        _metadata = State(initialValue: viewModel.metadata)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Players".localized) {
                    HStack {
                        TextField("Black Name".localized, text: $metadata.blackName)
                        TextField("Rank".localized, text: $metadata.blackRank)
                            .frame(width: 60)
                    }
                    HStack {
                        TextField("White Name".localized, text: $metadata.whiteName)
                        TextField("Rank".localized, text: $metadata.whiteRank)
                            .frame(width: 60)
                    }
                }

                Section("Game Info".localized) {
                    TextField("Game Name".localized, text: $metadata.gameName)
                    TextField("Event".localized, text: $metadata.event)
                    TextField("Date".localized, text: $metadata.date)
                    TextField("Place".localized, text: $metadata.place)
                    TextField("Result".localized, text: $metadata.result)
                }

                Section("Rules".localized) {
                    HStack {
                        Text("Komi".localized)
                        Spacer()
                        TextField("", value: $metadata.komi, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Game Info".localized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save".localized) {
                        viewModel.updateMetadata(metadata)
                        dismiss()
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 500)
        }
    }
}
