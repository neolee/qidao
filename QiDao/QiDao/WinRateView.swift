import SwiftUI

struct WinRateView: View {
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject private var langManager = LanguageManager.shared

    var body: some View {
        GroupBox(label: Label("Win Rate".localized, systemImage: "chart.line.uptrend.xyaxis")) {
            VStack(spacing: 12) {
                // Real-time win rate bar
                let isStale = viewModel.analysisResult == nil || viewModel.analysisResult?.id.hasSuffix("-\(viewModel.currentNodeId)") == false
                let winRate = viewModel.analysisResult?.rootInfo.winrate ?? 0.5
                VStack(spacing: 4) {
                    HStack {
                        Text(String(format: "B: %.1f%%", winRate * 100))
                            .font(.caption.bold())
                        Spacer()
                        Text(String(format: "W: %.1f%%", (1.0 - winRate) * 100))
                            .font(.caption.bold())
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white)
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: geo.size.width * CGFloat(winRate))
                        }
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .opacity(isStale ? 0.6 : 1.0)
                    }
                    .frame(height: 12)
                }

                // Win Rate Graph
                if viewModel.config.display.showWinRateGraph {
                    Group {
                        if viewModel.isAnalyzing {
                            let maxCount = viewModel.maxMoveCount
                            let totalMoves = maxCount <= 100 ? 100 : ((maxCount + 49) / 50) * 50
                            WinRateGraph(history: viewModel.winRateHistory, blunders: viewModel.blunders, currentTurn: viewModel.moveCount, totalMoves: totalMoves) { turn in
                                viewModel.jumpToMove(min(turn, viewModel.maxMoveCount))
                            }
                        } else {
                            Text("AI Analysis Inactive".localized)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.05))
                                .cornerRadius(4)
                        }
                    }
                    .frame(height: 80)
                    .padding(.top, 5)
                }
            }
            .padding(5)
        }
    }
}

struct WinRateGraph: View {
    let history: [Int: Double]
    let blunders: [Int: BoardViewModel.BlunderType]
    let currentTurn: Int
    let totalMoves: Int
    var onTap: ((Int) -> Void)? = nil

    @State private var hoverLocation: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            let step = geo.size.width / CGFloat(max(totalMoves, 1))

            ZStack(alignment: .topLeading) {
                // Background grid (0%, 50%, 100% lines)
                Path { path in
                    // 100% line (Top)
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width, y: 0))

                    // 50% line (Center)
                    path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))

                    // 0% line (Bottom)
                    path.move(to: CGPoint(x: 0, y: geo.size.height))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                }
                .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [2]))

                // Win rate line
                Path { path in
                    let sortedKeys = history.keys.sorted()
                    guard !sortedKeys.isEmpty else { return }

                    var first = true
                    for turn in sortedKeys {
                        if let rate = history[turn] {
                            let x = CGFloat(turn) * step
                            let y = geo.size.height * CGFloat(1.0 - rate)
                            if first {
                                path.move(to: CGPoint(x: x, y: y))
                                first = false
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                }
                .stroke(Color.blue, lineWidth: 1.5)

                // Blunder markers
                ForEach(blunders.keys.sorted(), id: \.self) { turn in
                    if let rate = history[turn] {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 4, height: 4)
                            .position(x: CGFloat(turn) * step, y: geo.size.height * CGFloat(1.0 - rate))
                    }
                }

                // Current turn indicator
                let currentX = CGFloat(currentTurn) * step
                Rectangle()
                    .fill(Color.red.opacity(0.5))
                    .frame(width: 1)
                    .position(x: currentX, y: geo.size.height / 2)

                // Hover indicator
                if let loc = hoverLocation {
                    let turn = Int(round(loc.x / step))
                    let clampedTurn = max(0, min(turn, totalMoves))
                    let hoverX = CGFloat(clampedTurn) * step

                    // Vertical dashed line
                    Path { path in
                        path.move(to: CGPoint(x: hoverX, y: 0))
                        path.addLine(to: CGPoint(x: hoverX, y: geo.size.height))
                    }
                    .stroke(Color.red.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2]))

                    // Win rate tooltip
                    if let rate = history[clampedTurn] {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "Move %d".localized, clampedTurn))
                                .font(.system(size: 9, weight: .bold))
                            HStack(spacing: 4) {
                                Text(String(format: "%.1f%%", rate * 100))
                                    .font(.system(size: 9))
                                if blunders[clampedTurn] != nil {
                                    Text("Blunder".localized)
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .position(x: hoverX, y: 15)
                    }
                }
            }
            .background(Color.black.opacity(0.05))
            .contentShape(Rectangle())
            .clipped()
            .onTapGesture { location in
                let turn = Int(round(location.x / step))
                onTap?(max(0, min(turn, totalMoves)))
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                    NSCursor.pointingHand.set()
                case .ended:
                    hoverLocation = nil
                    NSCursor.arrow.set()
                }
            }
            .cornerRadius(4)
        }
    }
}
