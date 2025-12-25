import SwiftUI
import UniformTypeIdentifiers
import qidao_coreFFI

struct BoardView: View {
    @StateObject private var viewModel = BoardViewModel()
    @ObservedObject private var langManager = LanguageManager.shared
    @FocusState private var isBoardFocused: Bool

    var body: some View {
        HSplitView {
            // Left Sidebar: Game Info & AI Logs
            VStack(alignment: .leading, spacing: 20) {
                GroupBox(label: Label("Game Info".localized, systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(viewModel.gameInfo)
                            .font(.caption)
                        Divider()
                        Text("\("Next".localized): \(viewModel.nextColor == .black ? "Black".localized : "White".localized)")
                            .fontWeight(.bold)
                    }
                    .padding(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: Label("Win Rate".localized, systemImage: "chart.line.uptrend.xyaxis")) {
                    Text("Chart Placeholder")
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.05))
                }

                GroupBox(label: Label("AI Logs".localized, systemImage: "terminal")) {
                    ScrollView {
                        Text("GTP Log Placeholder...")
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding()
            .frame(minWidth: 200, maxWidth: 300)

            // Center: Board & Toolbar
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
                            MainBoardView(viewModel: viewModel, size: size)
                            Spacer()
                        }
                        Spacer()
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        isBoardFocused = true
                    }
                )
                .focusable()
                .focused($isBoardFocused)
                .focusEffectDisabled()
                .onAppear {
                    isBoardFocused = true
                }

                // Navigation Toolbar
                HStack(spacing: 20) {
                    Button(action: viewModel.goBack) {
                        Image(systemName: "chevron.left.circle")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Previous Move (↑)")

                    Text("Move".localized + " \(viewModel.moveNumbers.count)")
                        .font(.headline)
                        .frame(width: 100)

                    Button(action: viewModel.goForward) {
                        Image(systemName: "chevron.right.circle")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Next Move (↓)")
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.05))
            }
            .frame(minWidth: 400)

            // Right Sidebar: Variations & Analysis
            VStack(alignment: .leading, spacing: 20) {
                GroupBox(label: Label("Variation Tree".localized, systemImage: "arrow.triangle.branch")) {
                    Text("Tree Placeholder")
                        .frame(maxHeight: .infinity)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.05))
                }

                GroupBox(label: Label("AI Analysis".localized, systemImage: "list.bullet.rectangle")) {
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
        .onKeyPress(.upArrow) {
            viewModel.goBack()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.goForward()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            // TODO: Previous branch
            return .handled
        }
        .onKeyPress(.rightArrow) {
            // TODO: Next branch
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
        // Restore focus to the board after the dialog closes
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
        // Restore focus to the board after the dialog closes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isBoardFocused = true
        }
    }
}

struct MainBoardView: View {
    @ObservedObject var viewModel: BoardViewModel
    let size: CGFloat
    let gridSize: Int = 19

    var body: some View {
        let spacing = size / CGFloat(gridSize + 1)

        ZStack {
            // 1. Background
            RoundedRectangle(cornerRadius: 2)
                .fill(viewModel.theme.boardColor)
                .shadow(color: .black.opacity(0.2), radius: 5)

            // 2. Coordinates (Optional)
            if viewModel.showCoordinates {
                BoardCoordinates(gridSize: gridSize, spacing: spacing)
                    .foregroundColor(viewModel.theme.lineColor)
            }

            // 3. Grid Lines
            BoardGrid(gridSize: gridSize)
                .stroke(viewModel.theme.lineColor, lineWidth: viewModel.theme.gridLineWidth)

            // 4. Star Points (Hoshi)
            StarPoints(gridSize: gridSize)
                .fill(viewModel.theme.starPointColor)

            // 5. Stones & Numbers
            GeometryReader { geometry in
                ForEach(0..<gridSize, id: \.self) { y in
                    ForEach(0..<gridSize, id: \.self) { x in
                        if let color = viewModel.board.getStone(x: UInt32(x), y: UInt32(y)) {
                            let moveNum = viewModel.moveNumbers["\(x),\(y)"]

                            StoneView(
                                color: color,
                                theme: viewModel.theme,
                                size: spacing * 0.95,
                                moveNumber: viewModel.showMoveNumbers ? moveNum : nil,
                                isLastMove: viewModel.lastMove?.x == x && viewModel.lastMove?.y == y
                            )
                            .position(
                                x: CGFloat(x + 1) * spacing,
                                y: CGFloat(y + 1) * spacing
                            )
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    let x = Int(round(value.location.x / spacing)) - 1
                    let y = Int(round(value.location.y / spacing)) - 1

                    if x >= 0 && x < gridSize && y >= 0 && y < gridSize {
                        viewModel.placeStone(x: x, y: y)
                    }
                }
        )
    }
}

// MARK: - Helper Views

struct StoneView: View {
    let color: StoneColor
    let theme: BoardTheme
    let size: CGFloat
    let moveNumber: Int?
    let isLastMove: Bool

    var body: some View {
        let style = (color == .black) ? theme.blackStoneStyle : theme.whiteStoneStyle

        ZStack {
            // 1. Last move marker (outer edge)
            if isLastMove {
                Circle()
                    .stroke(theme.lastMoveMarkerColor, lineWidth: 1)
                    .frame(width: size + 4, height: size + 4)
            }

            // 2. Stone Shadow (3D effect)
            Circle()
                .fill(style.shadowColor)
                .offset(x: 1.5, y: 2.0)
                .frame(width: size, height: size)
                .blur(radius: 5)

            // 3. Stone Body
            Circle()
                .fill(style.fill)
                .frame(width: size, height: size)

            // 4. Subtle 3D Highlight
            if style.hasHighlight {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(color == .black ? 0.3 : 0.6),
                                .clear
                            ],
                            center: .init(x: 0.3, y: 0),
                            startRadius: 0,
                            endRadius: size * 0.5
                        )
                    )
                    .frame(width: size, height: size)
            }

            // 5. Stroke (if any)
            if style.strokeWidth > 0 {
                Circle()
                    .stroke(style.strokeColor, lineWidth: style.strokeWidth)
                    .frame(width: size, height: size)
            }

            // 6. Move Number
            if let num = moveNumber {
                Text("\(num)")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundColor(style.textColor)
            }
        }
    }
}

struct BoardCoordinates: View {
    let gridSize: Int
    let spacing: CGFloat

    private let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T"]

    var body: some View {
        ZStack {
            // Top & Bottom (Letters)
            ForEach(0..<gridSize, id: \.self) { i in
                Text(letters[i])
                    .font(.system(size: spacing * 0.3, weight: .medium))
                    .position(x: CGFloat(i + 1) * spacing, y: spacing * 0.4)

                Text(letters[i])
                    .font(.system(size: spacing * 0.3, weight: .medium))
                    .position(x: CGFloat(i + 1) * spacing, y: CGFloat(gridSize + 1) * spacing - spacing * 0.4)
            }

            // Left & Right (Numbers)
            ForEach(0..<gridSize, id: \.self) { i in
                let label = "\(gridSize - i)"
                Text(label)
                    .font(.system(size: spacing * 0.3, weight: .medium))
                    .position(x: spacing * 0.4, y: CGFloat(i + 1) * spacing)

                Text(label)
                    .font(.system(size: spacing * 0.3, weight: .medium))
                    .position(x: CGFloat(gridSize + 1) * spacing - spacing * 0.4, y: CGFloat(i + 1) * spacing)
            }
        }
    }
}

struct BoardGrid: Shape {
    let gridSize: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing = rect.width / CGFloat(gridSize + 1)

        for i in 1...gridSize {
            // Vertical lines
            path.move(to: CGPoint(x: CGFloat(i) * spacing, y: spacing))
            path.addLine(to: CGPoint(x: CGFloat(i) * spacing, y: rect.height - spacing))

            // Horizontal lines
            path.move(to: CGPoint(x: spacing, y: CGFloat(i) * spacing))
            path.addLine(to: CGPoint(x: rect.width - spacing, y: CGFloat(i) * spacing))
        }

        return path
    }
}

struct StarPoints: Shape {
    let gridSize: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing = rect.width / CGFloat(gridSize + 1)
        let radius: CGFloat = 3

        let points: [Int]
        if gridSize == 19 {
            points = [4, 10, 16]
        } else if gridSize == 13 {
            points = [4, 7, 10]
        } else if gridSize == 9 {
            points = [3, 5, 7]
        } else {
            points = []
        }

        for row in points {
            for col in points {
                let center = CGPoint(x: CGFloat(col) * spacing, y: CGFloat(row) * spacing)
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
        }

        return path
    }
}

#Preview {
    BoardView()
}
