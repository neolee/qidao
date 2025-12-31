import SwiftUI

struct PlayControlView: View {
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject private var langManager = LanguageManager.shared
    @State private var showNewGameDialog = false

    private var roleBinding: Binding<AIRole> {
        Binding(
            get: { viewModel.aiRole },
            set: { newValue in
                DispatchQueue.main.async {
                    viewModel.aiRole = newValue
                }
            }
        )
    }

    var body: some View {
        GroupBox(label: Label("Play Control".localized, systemImage: "gamecontroller")) {
            VStack(spacing: 12) {
                // 1. AI Role Selection
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Role".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("AI Role".localized, selection: roleBinding) {
                        ForEach(AIRole.allCases) { role in
                            Label(role.label, systemImage: role.icon).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .id(langManager.selectedLanguage)
                }

                Divider()

                // 2. New Game Button
                Button(action: { showNewGameDialog = true }) {
                    Label("New Game".localized, systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Divider()

                // 3. Control Buttons
                HStack(spacing: 10) {
                    ActionButton(title: "Pass".localized, icon: "hand.raised.fill", color: .orange) {
                        viewModel.pass()
                    }
                    ActionButton(title: "Resign".localized, icon: "flag.fill", color: .red) {
                        viewModel.resign()
                    }
                }

                HStack(spacing: 10) {
                    ActionButton(title: "Undo".localized, icon: "arrow.uturn.backward", color: .blue) {
                        viewModel.goBack()
                    }
                    ActionButton(title: "Restart".localized, icon: "arrow.counterclockwise", color: .gray) {
                        viewModel.goToStart()
                    }
                }
            }
            .padding(8)
        }
        .sheet(isPresented: $showNewGameDialog) {
            NewGameDialog(viewModel: viewModel)
        }
    }
}

struct NewGameDialog: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject private var langManager = LanguageManager.shared
    @State private var size: Int = 19
    @State private var komi: Double = 7.5
    @State private var handicap: Int = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("Start New Game".localized)
                .font(.headline)

            Form {
                Picker("Board Size".localized, selection: $size) {
                    Text("19 x 19").tag(19)
                    Text("13 x 13").tag(13)
                    Text("9 x 9").tag(9)
                }

                TextField("Komi".localized, value: $komi, format: .number)
                    .disabled(handicap > 0)
                    .opacity(handicap > 0 ? 0.5 : 1.0)

                Stepper("Handicap".localized + ": \(handicap)", value: $handicap, in: 0...9)
            }
            .formStyle(.grouped)
            .frame(width: 300, height: 150)

            HStack {
                Button("Cancel".localized) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Start".localized) {
                    viewModel.startNewGame(size: size, komi: komi, handicap: handicap)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    @ObservedObject private var langManager = LanguageManager.shared

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .foregroundColor(color)
    }
}
