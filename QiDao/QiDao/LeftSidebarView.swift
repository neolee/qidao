import SwiftUI
import qidao_coreFFI

struct LeftSidebarView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Binding var showInfoEditor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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

            GroupBox(label: Label("AI Analysis".localized, systemImage: "cpu")) {
                VStack(spacing: 10) {
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

                    if viewModel.isAnalyzing {
                        HStack {
                            CustomSpinner()
                            Text("Analyzing...".localized)
                                .font(.caption)
                        }
                    }
                }
                .padding(5)
            }

            GroupBox(label: Label("Win Rate".localized, systemImage: "chart.line.uptrend.xyaxis")) {
                Text("Chart Placeholder")
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.05))
            }

            GroupBox(label: Label("Engine Logs".localized, systemImage: "terminal")) {
                ScrollView {
                    Text("GTP Log Placeholder...")
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            }
            .textSelection(.enabled)
        }
        .padding()
        .frame(minWidth: 200, maxWidth: 300)
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
