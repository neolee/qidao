import SwiftUI
import qidao_coreFFI

struct LeftSidebarView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Binding var showInfoEditor: Bool
    @Binding var showEngineConfig: Bool
    @ObservedObject private var langManager = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            GroupBox(label: Label("Game Info".localized, systemImage: "info.circle")) {
                VStack(alignment: .leading, spacing: 8) {
                    if !viewModel.metadata.gameName.isEmpty {
                        Text(viewModel.metadata.gameName)
                            .font(.headline)
                            .padding(.bottom, 4)
                    }
                    if !viewModel.metadata.event.isEmpty {
                        InfoRow(label: "Event".localized, value: viewModel.metadata.event)
                    }
                    if !viewModel.metadata.date.isEmpty {
                        InfoRow(label: "Date".localized, value: viewModel.metadata.date)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Black".localized).font(.caption).foregroundColor(.secondary)
                            Text(viewModel.metadata.blackName.isEmpty ? "Black".localized : viewModel.metadata.blackName)
                                .fontWeight(.bold)
                                .lineLimit(1)
                            if !viewModel.metadata.blackRank.isEmpty {
                                Text(viewModel.metadata.blackRank).font(.caption)
                            }
                        }
                        Spacer()
                        Text("vs".localized).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("White".localized).font(.caption).foregroundColor(.secondary)
                            Text(viewModel.metadata.whiteName.isEmpty ? "White".localized : viewModel.metadata.whiteName)
                                .fontWeight(.bold)
                                .lineLimit(1)
                            if !viewModel.metadata.whiteRank.isEmpty {
                                Text(viewModel.metadata.whiteRank).font(.caption)
                            }
                        }
                    }

                    Divider()

                    InfoRow(label: "Komi".localized, value: String(format: "%.1f", viewModel.metadata.komi))
                    if !viewModel.metadata.result.isEmpty {
                        InfoRow(label: "Result".localized, value: viewModel.formattedResult)
                    }

                    Text("\("Next".localized): \(viewModel.nextColor == .black ? "Black".localized : "White".localized)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .padding(.top, 4)

                    Button(action: { showInfoEditor = true }) {
                        Label("Edit".localized, systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 5)
                    .focusable(false)
                }
                .padding(5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .textSelection(.enabled)

            GroupBox(label: Label("Win Rate".localized, systemImage: "chart.line.uptrend.xyaxis")) {
                VStack(spacing: 12) {
                    // Real-time win rate bar
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
                        }
                        .frame(height: 12)
                    }

                    // Win Rate Graph
                    if viewModel.config.display.showWinRateGraph {
                        if viewModel.isAnalyzing {
                            let maxCount = viewModel.maxMoveCount
                            let totalMoves = maxCount <= 100 ? 100 : ((maxCount + 49) / 50) * 50
                            WinRateGraph(history: viewModel.winRateHistory, currentTurn: viewModel.moveCount, totalMoves: totalMoves) { turn in
                                viewModel.jumpToMove(min(turn, viewModel.maxMoveCount))
                            }
                                .frame(height: 80)
                                .padding(.top, 5)
                        } else {
                            Text("AI Analysis Inactive".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(height: 80)
                                .frame(maxWidth: .infinity)
                                .background(Color.black.opacity(0.05))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(5)
            }

            GroupBox(label: Label("AI Engine".localized, systemImage: "cpu")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button(action: { viewModel.toggleAnalysis() }) {
                            Label(
                                viewModel.isAnalyzing ? "Stop AI".localized : "Start AI".localized,
                                systemImage: viewModel.isAnalyzing ? "stop.fill" : "play.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.isAnalyzing ? .red : .blue)
                        .focusable(false)

                        Button(action: { showEngineConfig = true }) {
                            Image(systemName: "gearshape")
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.bordered)
                        .focusable(false)
                    }

                    HStack(spacing: 8) {
                        if viewModel.isAnalyzing {
                            CustomSpinner()
                        } else {
                            Image(systemName: "pause.circle")
                                .foregroundColor(.secondary)
                        }

                        Text(viewModel.engineMessage)
                            .font(.caption)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 5)

                    Divider()

                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: 5) {
                            ScrollView {
                                // Render logs as a single selectable text block so user can select multiple lines
                                let filteredEntries = viewModel.logEntries.filter { entry in
                                    if viewModel.showAllLogs { return true }
                                    return entry.isError || !entry.isCommunication
                                }
                                let combined = filteredEntries.map { $0.message }.joined(separator: "\n")

                                Text(combined.isEmpty ? (viewModel.showAllLogs ? "No logs...".localized : "No errors...".localized) : combined)
                                    .font(.system(size: 10, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)

                                Color.clear
                                    .frame(height: 1)
                                    .id("logEnd")
                            }
                            .frame(maxHeight: .infinity)
                            .onChange(of: viewModel.logEntries.count) {
                                withAnimation {
                                    proxy.scrollTo("logEnd", anchor: .bottom)
                                }
                            }

                            Toggle("Show All Logs".localized, isOn: $viewModel.showAllLogs)
                                .font(.caption)
                                .padding(.horizontal, 4)
                                .padding(.bottom, 4)
                        }
                    }
                    .background(Color.black.opacity(0.03))
                    .cornerRadius(4)
                }
                .padding(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .textSelection(.enabled)
        }
        .padding()
        .frame(minWidth: 250, maxWidth: 350)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

struct WinRateGraph: View {
    let history: [Int: Double]
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
                        Text(String(format: "%.1f%%", rate * 100))
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .position(x: hoverX, y: 12) // Move inside the graph area to avoid clipping
                    }
                }
            }
            .background(Color.black.opacity(0.05))
            .contentShape(Rectangle())
            .clipped() // Ensure nothing spills out, but tooltip is now inside
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

struct CustomSpinner: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.accentColor, lineWidth: 2)
            .frame(width: 12, height: 12)
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(Animation.linear(duration: 1).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}
