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

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button(action: openSgf) {
                    Label("Open".localized, systemImage: "doc.badge.plus")
                }
                .focusable(false)
                Button(action: saveSgf) {
                    Label("Save".localized, systemImage: "square.and.arrow.down")
                }
                .focusable(false)

                Divider().frame(height: 20)

                Button(action: viewModel.toggleTheme) {
                    Label("Theme".localized, systemImage: "paintpalette")
                }
                .focusable(false)
                Button(action: viewModel.resetBoard) {
                    Label("Reset".localized, systemImage: "arrow.counterclockwise")
                }
                .focusable(false)

                Divider().frame(height: 20)

                Toggle("Numbers".localized, isOn: $viewModel.showMoveNumbers)
                    .toggleStyle(.checkbox)
                    .focusable(false)
                Toggle("Coordinates".localized, isOn: $viewModel.showCoordinates)
                    .toggleStyle(.checkbox)
                    .focusable(false)
                Toggle("Sound".localized, isOn: $viewModel.playSound)
                    .toggleStyle(.checkbox)
                    .focusable(false)

                Spacer()

                Menu {
                    ForEach(Language.allCases) { lang in
                        Button(lang.displayName) {
                            DispatchQueue.main.async {
                                langManager.selectedLanguage = lang
                            }
                        }
                    }
                } label: {
                    Label(langManager.selectedLanguage.displayName, systemImage: "globe")
                }
                .menuStyle(.button)
                .frame(width: 120)
                .focusable(false)

                Text(viewModel.message)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            .padding()
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
                        TextField("0-\(viewModel.maxMoveCount)", text: $jumpToMoveInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.center)
                            .focused($isJumpFieldFocused)
                            .onSubmit {
                                let targetMove = Int(jumpToMoveInput)
                                isJumpFieldFocused = false
                                if let move = targetMove {
                                    viewModel.jumpToMove(move)
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    isBoardFocused = true
                                }
                            }
                            .onExitCommand {
                                isJumpFieldFocused = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    isBoardFocused = true
                                }
                            }
                            .onChange(of: isJumpFieldFocused) { old, new in
                                if !new {
                                    isEditingMoveNumber = false
                                }
                            }
                    } else {
                        Button(action: {
                            jumpToMoveInput = ""
                            isEditingMoveNumber = true
                            DispatchQueue.main.async {
                                isJumpFieldFocused = true
                            }
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
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
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
    }

    private func openSgf() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "sgf")!]

        if panel.runModal() == .OK {
            if let url = panel.url {
                viewModel.loadSgf(url: url)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isBoardFocused = true
        }
    }

    private func saveSgf() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "sgf")!]
        panel.nameFieldStringValue = "game.sgf"

        if panel.runModal() == .OK {
            if let url = panel.url {
                viewModel.saveSgf(url: url)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isBoardFocused = true
        }
    }
}

#Preview {
    @Previewable @FocusState var isBoardFocused: Bool
    CenterView(viewModel: BoardViewModel(), isBoardFocused: $isBoardFocused)
}
