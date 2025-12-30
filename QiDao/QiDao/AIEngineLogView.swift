import SwiftUI

struct AIEngineLogView: View {
    @ObservedObject var viewModel: BoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.logEntries) { entry in
                            if viewModel.showAllLogs || entry.type != .raw {
                                Text(entry.message)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(colorForType(entry.type))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .id("logContent")

                    Color.clear
                        .frame(height: 1)
                        .id("logEnd")
                }
                .onChange(of: viewModel.logEntries.count) {
                    proxy.scrollTo("logEnd", anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo("logEnd", anchor: .bottom)
                }
            }
            .padding(5)
            .background(Color.black.opacity(0.03))
            .cornerRadius(4)

            Toggle("Developer Mode".localized, isOn: $viewModel.showAllLogs)
                .font(.caption)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
    }

    private func colorForType(_ type: LogType) -> Color {
        switch type {
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        case .play: return .blue
        case .analysis: return .green
        case .fullScan: return .purple
        case .raw: return .secondary
        }
    }
}
