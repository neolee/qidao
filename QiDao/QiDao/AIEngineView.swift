import SwiftUI

struct AIEngineView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Binding var showAIConfig: Bool
    @ObservedObject private var langManager = LanguageManager.shared

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
                    Image(systemName: viewModel.aiStatus.icon)
                        .foregroundColor(viewModel.aiStatus.color)
                        .symbolEffect(.pulse, options: .repeating, isActive: viewModel.aiStatus == .thinking || viewModel.aiStatus == .analyzing || viewModel.aiStatus == .starting)

                    Text(viewModel.engineMessage)
                        .font(.caption)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 5)
                .frame(height: 20)
            }
            .padding(5)
            .frame(maxWidth: .infinity)
        }
        .textSelection(.enabled)
    }
}
