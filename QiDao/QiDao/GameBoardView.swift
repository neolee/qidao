import SwiftUI
import qidao_coreFFI

struct GameBoardView: View {
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
                            StoneView(
                                color: color,
                                theme: viewModel.theme,
                                size: spacing * 0.95,
                                moveNumber: viewModel.getDisplayMoveNumber(x: x, y: y),
                                isLastMove: viewModel.lastMove?.x == x && viewModel.lastMove?.y == y
                            )
                            .position(
                                x: CGFloat(x + 1) * spacing,
                                y: CGFloat(y + 1) * spacing
                            )
                        }
                    }
                }

                // 6. Variation Markers
                ForEach(viewModel.variations, id: \.id) { variation in
                    if let vx = variation.x, let vy = variation.y {
                        VariationMarker(
                            label: variation.label,
                            theme: viewModel.theme,
                            size: spacing * 0.8
                        )
                        .position(
                            x: CGFloat(vx + 1) * spacing,
                            y: CGFloat(vy + 1) * spacing
                        )
                        .onTapGesture {
                            viewModel.selectVariation(variation.id)
                        }
                    }
                }

                // 7. AI Analysis Overlay
                if let result = viewModel.analysisResult {
                    let maxVisits = result.moveInfos.map { $0.visits }.max() ?? 0
                    ForEach(result.moveInfos, id: \.moveStr) { info in
                        if let pos = viewModel.decodeKataGoMove(info.moveStr) {
                            AIMoveMarker(
                                winRate: info.winrate,
                                scoreLead: info.scoreLead,
                                isBest: info.visits == maxVisits && maxVisits > 0,
                                theme: viewModel.theme,
                                size: spacing * 0.95
                            )
                            .position(
                                x: CGFloat(pos.x + 1) * spacing,
                                y: CGFloat(pos.y + 1) * spacing
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

struct AIMoveMarker: View {
    let winRate: Double
    let scoreLead: Double
    let isBest: Bool
    let theme: BoardTheme
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(isBest ? Color.blue.opacity(0.8) : Color.green.opacity(0.6))
                .frame(width: size, height: size)
                .shadow(radius: 2)
            
            VStack(spacing: 0) {
                Text(String(format: "%.1f%%", winRate * 100))
                    .font(.system(size: size * 0.25, weight: .bold))
                    .foregroundColor(.white)
                Text(String(format: "%+.1f", scoreLead))
                    .font(.system(size: size * 0.2, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }
}
