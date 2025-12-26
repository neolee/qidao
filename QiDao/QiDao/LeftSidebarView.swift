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
                VStack(spacing: 10) {
                    // Real-time win rate bar (placeholder)
                    Text("Win Rate Bar Placeholder")
                        .font(.caption)
                        .frame(height: 20)
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))

                    // Chart placeholder
                    Text("Chart Placeholder")
                        .font(.caption)
                        .frame(height: 100)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.05))
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
                            Text(viewModel.engineLogs.isEmpty ? "No logs...".localized : viewModel.engineLogs)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("logEnd")
                        }
                        .frame(maxHeight: .infinity)
                        .onChange(of: viewModel.engineLogs) {
                            proxy.scrollTo("logEnd", anchor: .bottom)
                        }
                    }
                    .background(Color.black.opacity(0.03))
                    .cornerRadius(4)
                }
                .padding(5)
                .frame(maxHeight: .infinity)
            }
            .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 250, maxWidth: 350)
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
