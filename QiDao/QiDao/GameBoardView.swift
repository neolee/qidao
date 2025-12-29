import SwiftUI
import qidao_coreFFI

struct GameBoardView: View {
    @ObservedObject var viewModel: BoardViewModel
    let size: CGFloat
    var gridSize: Int { viewModel.boardSize }

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
                if viewModel.isAnalyzing, let result = viewModel.analysisResult, result.id.hasSuffix("-\(viewModel.currentNodeId)") {
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
                                if index == 0 { return viewModel.theme.aiBestMoveColor }
                                // Compare win rates in Black's perspective (both are normalized to Black)
                                if abs(info.winrate - bestMoveWinRate) <= 0.01 {
                                    return viewModel.theme.aiGoodMoveColor
                                }
                                return viewModel.theme.aiCandidateMoveColor
                            }()

                            ZStack {
                                // 1. Stable Hover Target (Transparent but hit-testable)
                                // Using a Rectangle ensures the entire intersection area captures the hover
                                Color.white.opacity(0.001)
                                    .frame(width: spacing, height: spacing)
                                    .onHover { hovering in
                                        withAnimation(.easeInOut(duration: 0.1)) {
                                            if hovering {
                                                viewModel.hoveredMoveStr = info.moveStr
                                            } else if viewModel.hoveredMoveStr == info.moveStr {
                                                viewModel.hoveredMoveStr = nil
                                            }
                                        }
                                    }

                                // 2. Visual Marker
                                AIMoveMarker(
                                    winRate: displayWinRate,
                                    scoreLead: displayScoreLead,
                                    visits: Int(info.visits),
                                    rank: index + 1,
                                    color: markerColor,
                                    textColor: viewModel.theme.aiMarkerTextColor,
                                    size: spacing * 0.95
                                )
                                .opacity(viewModel.hoveredMoveStr == nil ? 1.0 : 0.0)
                                .allowsHitTesting(false) // Don't let the marker interfere with the hover target
                            }
                            .position(
                                x: CGFloat(pos.x + 1) * spacing,
                                y: CGFloat(pos.y + 1) * spacing
                            )
                        }
                    }
                }

                // 9. Hovered Variation Preview
                if let hoveredMove = viewModel.hoveredMoveStr,
                   let result = viewModel.analysisResult,
                   let info = result.moveInfos.first(where: { $0.moveStr == hoveredMove }) {
                    let pv = info.pv
                    let nextColor = viewModel.nextColor
                    ForEach(Array(pv.enumerated()), id: \.offset) { index, moveStr in
                        if let pos = viewModel.decodeKataGoMove(moveStr) {
                            let stoneColor: StoneColor = (index % 2 == 0) ? nextColor : (nextColor == .black ? .white : .black)
                            StoneView(
                                color: stoneColor,
                                theme: viewModel.theme,
                                size: spacing * 0.95,
                                moveNumber: index + 1,
                                markerType: nil
                            )
                            .opacity(0.8)
                            .allowsHitTesting(false) // CRITICAL: Don't block hover events for markers below
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
