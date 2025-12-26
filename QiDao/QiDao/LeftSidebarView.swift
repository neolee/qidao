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
                        if !viewModel.winRateHistory.isEmpty {
                            WinRateGraph(history: viewModel.winRateHistory, currentTurn: viewModel.moveCount)
                                .frame(height: 80)
                                .padding(.top, 5)
                        } else {
                            Text("No analysis data".localized)
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

                        Text(viewModel.message)
                            .font(.caption)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 5)

                    Divider()

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(viewModel.engineLogs.isEmpty ? "No logs...".localized : viewModel.engineLogs)
                                    .font(.system(size: 10, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Color.clear
                                    .frame(height: 1)
                                    .id("logEnd")
                            }
                        }
                        .frame(maxHeight: .infinity)
                        .onChange(of: viewModel.engineLogs) {
                            withAnimation {
                                proxy.scrollTo("logEnd", anchor: .bottom)
                            }
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
    let history: [Double]
    let currentTurn: Int

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background grid
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [2]))

                // Win rate line
                Path { path in
                    guard history.count > 1 else { return }
                    let step = geo.size.width / CGFloat(max(history.count - 1, 1))

                    for (i, rate) in history.enumerated() {
                        let x = CGFloat(i) * step
                        let y = geo.size.height * CGFloat(1.0 - rate)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.blue, lineWidth: 2)

                // Current turn indicator
                if currentTurn < history.count {
                    let step = geo.size.width / CGFloat(max(history.count - 1, 1))
                    let x = CGFloat(currentTurn) * step
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 1)
                        .offset(x: x - geo.size.width / 2)
                }
            }
            .background(Color.black.opacity(0.05))
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
