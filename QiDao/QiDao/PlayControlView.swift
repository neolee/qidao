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
                // 0. Clock Display
                if viewModel.playTimeSettings.isEnabled, let clock = viewModel.clockState {
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Human".localized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                let isHumanTurn = viewModel.isHumanTurn
                                let elapsed = (clock.currentMoveStartTime.map { Date().timeIntervalSince($0) } ?? 0) + clock.elapsedTimeBeforePause
                                let remainingInMove = max(0, viewModel.playTimeSettings.humanSecondsPerMove - elapsed)
                                
                                HStack(alignment: .bottom, spacing: 4) {
                                    let reserveRemaining = max(0, clock.humanReserveRemaining - (remainingInMove == 0 ? (elapsed - viewModel.playTimeSettings.humanSecondsPerMove) : 0))
                                    Text(formatTime(reserveRemaining))
                                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    Text(String(format: "%02d", Int(ceil(remainingInMove))))
                                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        .foregroundColor(remainingInMove <= 5 ? .red : (isHumanTurn ? .primary : .secondary))
                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text("AI".localized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if viewModel.aiManager.aiStatus == .thinking {
                                    HStack(spacing: 4) {
                                        CustomSpinner()
                                        Text("Thinking...".localized)
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                } else {
                                    Text("Ready".localized)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)
                    }
                }

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
        .alert("Timeout".localized, isPresented: $viewModel.showTimeoutDialog) {
            Button("End Game".localized, role: .destructive) {
                viewModel.handleTimeout(endGame: true)
            }
            Button("Continue".localized, role: .cancel) {
                viewModel.handleTimeout(endGame: false)
            }
        } message: {
            Text("Time is up. Do you want to end the game?".localized)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

struct NewGameDialog: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject private var langManager = LanguageManager.shared
    @State private var size: Int = 19
    @State private var komi: Double = 7.5
    @State private var handicap: Int = 0
    @State private var timeSettings = PlayTimeSettings()
    @State private var humanReserveMinutes: Int = 5
    @State private var humanSecondsPerMove: Int = 30

    var body: some View {
        VStack(spacing: 0) {
            Text("Start New Game".localized)
                .font(.headline)
                .padding(.vertical, 15)

            ScrollView {
                VStack(spacing: 20) {
                    // Game Settings Group
                    GroupBox {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Board Size".localized)
                                Spacer()
                                Picker("", selection: $size) {
                                    Text("19 x 19").tag(19)
                                    Text("13 x 13").tag(13)
                                    Text("9 x 9").tag(9)
                                }
                                .frame(width: 100)
                            }

                            HStack {
                                Text("Komi".localized)
                                Spacer()
                                TextField("", value: $komi, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                    .disabled(handicap > 0)
                                    .opacity(handicap > 0 ? 0.5 : 1.0)
                            }

                            HStack {
                                Text("Handicap".localized)
                                Spacer()
                                Stepper("\(handicap)", value: $handicap, in: 0...9)
                            }
                        }
                        .padding(8)
                    }

                    // Time Control Group
                    GroupBox {
                        VStack(spacing: 12) {
                            Toggle("Enable Time Control".localized, isOn: Binding(
                                get: { timeSettings.isEnabled },
                                set: { newValue in
                                    DispatchQueue.main.async {
                                        timeSettings.isEnabled = newValue
                                    }
                                }
                            ))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if timeSettings.isEnabled {
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Human".localized).font(.caption).foregroundColor(.secondary)
                                    HStack {
                                        Text("Byo-yomi".localized)
                                        Spacer()
                                        TextField("", value: $humanSecondsPerMove, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 50)
                                        Text("sec".localized)
                                    }
                                    HStack {
                                        Text("Reserve".localized)
                                        Spacer()
                                        TextField("", value: $humanReserveMinutes, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 50)
                                        Text("min".localized)
                                    }
                                    
                                    Divider()
                                    
                                    Text("AI".localized).font(.caption).foregroundColor(.secondary)
                                    HStack {
                                        Text("Limit Type".localized)
                                        Spacer()
                                        Picker("", selection: Binding(
                                            get: { timeSettings.aiLimitType },
                                            set: { newValue in
                                                DispatchQueue.main.async {
                                                    timeSettings.aiLimitType = newValue
                                                    let config = ConfigManager.shared.config
                                                    if newValue == .visits {
                                                        timeSettings.aiLimitValue = Double((config.analysis.maxVisits ?? 1000) / 2)
                                                    } else if newValue == .time {
                                                        timeSettings.aiLimitValue = (config.analysis.maxTime ?? 20.0) / 2.0
                                                    }
                                                }
                                            }
                                        )) {
                                            ForEach(PlayTimeSettings.AILimitType.allCases) { type in
                                                Text(type.label).tag(type)
                                            }
                                        }
                                        .frame(width: 120)
                                    }
                                    
                                    if timeSettings.aiLimitType != .global {
                                        HStack {
                                            Text("Value".localized)
                                            Spacer()
                                            TextField("", value: $timeSettings.aiLimitValue, format: .number.precision(.fractionLength(0...1)).grouping(.never))
                                                .textFieldStyle(.roundedBorder)
                                                .multilineTextAlignment(.trailing)
                                                .frame(width: 70)
                                            Text(timeSettings.aiLimitType == .visits ? "visits".localized : "sec".localized)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)

            HStack {
                Button("Cancel".localized) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Start".localized) {
                    var finalSettings = timeSettings
                    finalSettings.humanReserveTime = TimeInterval(humanReserveMinutes * 60)
                    finalSettings.humanSecondsPerMove = TimeInterval(humanSecondsPerMove)
                    viewModel.startNewGame(size: size, komi: komi, handicap: handicap, timeSettings: finalSettings)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 20)
        }
        .padding(20)
        .frame(width: 350, height: 550)
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
