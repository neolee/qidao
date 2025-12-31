import SwiftUI
import UniformTypeIdentifiers
import qidao_coreFFI

struct CenterView: View {
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject private var langManager = LanguageManager.shared
    @FocusState.Binding var isBoardFocused: Bool
    @FocusState private var isJumpFieldFocused: Bool
    @State private var isEditingMoveNumber = false
    @State private var jumpToMoveInput = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Group {
                    Picker("Size".localized, selection: $viewModel.boardSize) {
                        Text("19").tag(19)
                        Text("13").tag(13)
                        Text("9").tag(9)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 50)
                    .labelsHidden()
                    .disabled(viewModel.isSizeLocked)
                    .onChange(of: viewModel.boardSize) { oldSize, newSize in
                        // Use async to avoid "Publishing changes from within view updates is not allowed"
                        // when the picker updates the value.
                        DispatchQueue.main.async {
                            viewModel.changeBoardSize(newSize)
                        }
                    }

                    ToolbarButton(title: "Open".localized, icon: "arrow.up.doc", action: openSgf)
                    ToolbarButton(title: "Save".localized, icon: "arrow.down.doc", action: saveSgf)

                    Divider().frame(height: 20)

                    ToolbarButton(title: "Theme".localized, icon: "paintpalette", action: viewModel.toggleTheme)
                    ToolbarButton(title: "Reset".localized, icon: "arrow.counterclockwise", action: viewModel.resetBoard)
                }

                Divider().frame(height: 20)

                Group {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            Text("Numbers".localized)
                                .foregroundColor(.secondary)
                            Picker("Numbers".localized, selection: $viewModel.moveNumberDisplay) {
                                ForEach(MoveNumberDisplay.allCases) { display in
                                    Text(display.label).tag(display)
                                }
                            }
                            .labelsHidden()
                            .id(langManager.selectedLanguage)
                        }
                        Picker("Numbers".localized, selection: $viewModel.moveNumberDisplay) {
                            ForEach(MoveNumberDisplay.allCases) { display in
                                Text(display.label).tag(display)
                            }
                        }
                        .labelsHidden()
                        .id(langManager.selectedLanguage)
                    }
                    .frame(minWidth: 100, maxWidth: 150)
                    .help("Move Numbers".localized)

                    Toggle(isOn: $viewModel.showCoordinates) {
                        ViewThatFits(in: .horizontal) {
                            Text("Coordinates".localized)
                            Image(systemName: "number")
                        }
                    }
                    .toggleStyle(.checkbox)
                    .help("Coordinates".localized)

                    Toggle(isOn: $viewModel.playSound) {
                        ViewThatFits(in: .horizontal) {
                            Text("Sound".localized)
                            Image(systemName: "speaker.wave.2")
                        }
                    }
                    .toggleStyle(.checkbox)
                    .help("Sound".localized)
                }
                .focusable(false)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)

            // Board Container
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height) * 0.95

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        GameBoardView(viewModel: viewModel, size: size)
                        Spacer()
                    }
                    Spacer()
                }
            }
            .contentShape(Rectangle())

            // Navigation Toolbar
            HStack(spacing: 15) {
                Button(action: { viewModel.goToStart() }) {
                    Image(systemName: "backward.end.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Go to Start".localized)

                Button(action: { viewModel.goBack() }) {
                    Image(systemName: "chevron.left.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Previous Move (↑)".localized)

                ZStack {
                    if isEditingMoveNumber {
                        TextField(String(format: "0-%d".localized, viewModel.maxMoveCount), text: $jumpToMoveInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.center)
                            .focused($isJumpFieldFocused)
                            .onSubmit {
                                if let move = Int(jumpToMoveInput) {
                                    viewModel.jumpToMove(move)
                                }
                                isEditingMoveNumber = false
                                isBoardFocused = true
                            }
                            .onExitCommand {
                                isEditingMoveNumber = false
                                isBoardFocused = true
                            }
                    } else {
                        Button(action: {
                            jumpToMoveInput = ""
                            isEditingMoveNumber = true
                            isJumpFieldFocused = true
                        }) {
                            Text("Move".localized + " \(viewModel.moveCount)")
                                .font(.headline)
                                .frame(width: 100)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help("Jump to Move".localized)
                    }
                }
                .frame(height: 32)

                Button(action: { viewModel.goForward() }) {
                    Image(systemName: "chevron.right.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Next Move (↓)".localized)

                Button(action: { viewModel.goToEnd() }) {
                    Image(systemName: "forward.end.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Go to End".localized)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.black.opacity(0.05))
        }
        .focusable()
        .focused($isBoardFocused)
        .focusEffectDisabled()
        .simultaneousGesture(
            TapGesture().onEnded {
                isBoardFocused = true
            }
        )
        .onKeyPress(.upArrow) {
            viewModel.goBack()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.goForward()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            viewModel.previousVariation()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.nextVariation()
            return .handled
        }
        .onDeleteCommand {
            if viewModel.moveCount > 0 {
                showDeleteConfirmation = true
            }
        }
        .alert("Delete Branch".localized, isPresented: $showDeleteConfirmation) {
            Button("Delete".localized, role: .destructive) {
                viewModel.deleteCurrentBranch()
                isBoardFocused = true
            }
            Button("Cancel".localized, role: .cancel) {
                isBoardFocused = true
            }
        } message: {
            Text("Delete current move and subsequent branches?".localized)
        }
    }

    private func openSgf() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "sgf")!]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                viewModel.loadSgf(url: url)
            }
            // 确保在对话框关闭后恢复焦点
            DispatchQueue.main.async {
                isBoardFocused = true
            }
        }
    }

    private func saveSgf() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "sgf")!]
        panel.nameFieldStringValue = "game.sgf"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                viewModel.saveSgf(url: url)
            }
            // 确保在对话框关闭后恢复焦点
            DispatchQueue.main.async {
                isBoardFocused = true
            }
        }
    }
}

struct ToolbarButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                Label(title, systemImage: icon)
                Label(title, systemImage: icon).labelStyle(.iconOnly)
            }
        }
        .focusable(false)
        .help(title)
    }
}

#Preview {
    @Previewable @FocusState var isBoardFocused: Bool
    CenterView(viewModel: BoardViewModel(), isBoardFocused: $isBoardFocused)
}
