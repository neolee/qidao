import SwiftUI

struct AIEngineView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Binding var showEngineConfig: Bool

    var body: some View {
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
}
