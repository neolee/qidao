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
                            let moveNum = viewModel.moveNumbers["\(x),\(y)"]
                            StoneView(
                                color: color,
                                theme: viewModel.theme,
                                size: spacing * 0.95,
                                moveNumber: viewModel.getDisplayMoveNumber(x: x, y: y),
                                markerType: viewModel.getMarkerType(x: x, y: y, moveNumber: moveNum)
                            )
                            .position(
                                x: CGFloat(x + 1) * spacing,
                                y: CGFloat(y + 1) * spacing
                            )
                        }
                    }
                }

                // 6. Variation Markers
                if viewModel.variations.count > 1 {
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
                }

                // 7. Next Move Highlight (SGF)
                // Only show when AI is active, and make it a large thin circle
                if viewModel.isAnalyzing, let nextMove = viewModel.nextSgfMove {
                    Circle()
                        .stroke(viewModel.theme.nextMoveMarkerColor.opacity(0.7), lineWidth: 2)
                        .frame(width: spacing * 0.98, height: spacing * 0.98)
                        .position(
                            x: CGFloat(nextMove.x + 1) * spacing,
                            y: CGFloat(nextMove.y + 1) * spacing
                        )
                }

                // 8. AI Analysis Overlay
                // Only show if the result matches the current board state
                if let result = viewModel.analysisResult, result.id == "qidao-\(viewModel.currentNodeId)" {
                    let sortedMoves = result.moveInfos.sorted { $0.visits > $1.visits }
                    let displayCount = min(sortedMoves.count, viewModel.config.display.maxCandidates)
                    let isWhiteTurn = viewModel.nextColor == .white
                    let perspective = viewModel.config.display.overlayWinRatePerspective
                    
                    // Best win rate from current player's perspective
                    let bestMoveWinRate = sortedMoves.first?.winrate ?? 0.5
                    
                    ForEach(Array(sortedMoves.prefix(displayCount).enumerated()), id: \.element.moveStr) { index, info in
                        if let pos = viewModel.decodeKataGoMove(info.moveStr) {
                            let displayWinRate = WinRateConverter.convertWinRate(
                                info.winrate,
                                reportedAs: .black,
                                target: perspective,
                                isWhiteTurn: isWhiteTurn
                            )
                            let displayScoreLead = WinRateConverter.convertScoreLead(
                                info.scoreLead,
                                reportedAs: .black,
                                target: perspective,
                                isWhiteTurn: isWhiteTurn
                            )
                            
                            let markerColor: Color = {
                                if index == 0 { return .blue }
                                // Compare win rates in Black's perspective (both are normalized to Black)
                                if abs(info.winrate - bestMoveWinRate) <= 0.01 {
                                    return .green
                                }
                                return .orange
                            }()
                            
                            AIMoveMarker(
                                winRate: displayWinRate,
                                scoreLead: displayScoreLead,
                                visits: Int(info.visits),
                                rank: index + 1,
                                color: markerColor,
                                size: spacing * 0.95
                            )
                            .onHover { hovering in
                                viewModel.hoveredVariation = hovering ? info.pv : nil
                            }
                            .position(
                                x: CGFloat(pos.x + 1) * spacing,
                                y: CGFloat(pos.y + 1) * spacing
                            )
                        }
                    }
                }

                // 9. Hovered Variation Preview
                if let pv = viewModel.hoveredVariation {
                    let nextColor = viewModel.nextColor
                    ForEach(Array(pv.enumerated()), id: \.offset) { index, moveStr in
                        if let pos = viewModel.decodeKataGoMove(moveStr) {
                            let stoneColor: StoneColor = (index % 2 == 0) ? nextColor : (nextColor == .black ? .white : .black)
                            StoneView(
                                color: stoneColor,
                                theme: viewModel.theme,
                                size: spacing * 0.8,
                                moveNumber: index + 1,
                                markerType: nil
                            )
                            .opacity(0.6)
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
    let markerType: MarkerType?
    var fontSize: CGFloat? = nil

    var body: some View {
        let style = (color == .black) ? theme.blackStoneStyle : theme.whiteStoneStyle

        ZStack {
            // 1. Stone Shadow (3D effect)
            Circle()
                .fill(style.shadowColor)
                .offset(x: 1.5, y: 2.0)
                .frame(width: size, height: size)
                .blur(radius: 5)

            // 2. Stone Body
            Circle()
                .fill(style.fill)
                .frame(width: size, height: size)

            // 3. Subtle 3D Highlight
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

            // 4. Stroke (if any)
            if style.strokeWidth > 0 {
                Circle()
                    .stroke(style.strokeColor, lineWidth: style.strokeWidth)
                    .frame(width: size, height: size)
            }

            // 5. Move Number or Marker
            if let num = moveNumber {
                Text("\(num)")
                    .font(.system(size: fontSize ?? (size * 0.4), weight: .bold))
                    .foregroundColor(style.textColor)
            } else if let marker = markerType {
                switch marker {
                case .last1:
                    // Hollow circle, half radius
                    Circle()
                        .stroke(style.textColor, lineWidth: 2)
                        .frame(width: size * 0.5, height: size * 0.5)
                case .last2, .last3:
                    // Small solid circle, 1/4 radius
                    Circle()
                        .fill(style.textColor)
                        .frame(width: size * 0.25, height: size * 0.25)
                }
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
    let visits: Int
    let rank: Int
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.7))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)

            VStack(spacing: -0.2) {
                // 1. Visits (Top, Small)
                Text("\(visits)")
                    .font(.system(size: size * 0.22, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))

                // 2. Win Rate (Center, Large)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(String(format: "%.1f", winRate * 100))
                        .font(.system(size: size * 0.32, weight: .bold))
                    Text("%")
                        .font(.system(size: size * 0.16, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.vertical, -2)

                // 3. Score Lead (Bottom, Small)
                Text(String(format: "%+.1f", scoreLead))
                    .font(.system(size: size * 0.22, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }

            // Rank number at top-right
            if rank <= 9 {
                Text("\(rank)")
                    .font(.system(size: size * 0.22, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.5))
                    )
                    .offset(x: size * 0.4, y: -size * 0.4)
            }
        }
    }
}
