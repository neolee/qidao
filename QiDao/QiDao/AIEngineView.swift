import SwiftUI

struct AIEngineView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Binding var showAIConfig: Bool

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

                    Button(action: { showAIConfig = true }) {
                        Image(systemName: "gearshape")
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.bordered)
                    .focusable(false)
                }

                HStack(spacing: 8) {
                    if viewModel.isAnalyzing {
                        switch viewModel.aiState {
                        case .thinking:
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 16, height: 16)
                        case .analyzing:
                            CustomSpinner()
                        case .ready:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        case .idle:
                            Image(systemName: "circle")
                                .foregroundColor(.secondary)
                        }
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
            }
            .padding(5)
            .frame(maxWidth: .infinity)
        }
        .textSelection(.enabled)
    }
}
