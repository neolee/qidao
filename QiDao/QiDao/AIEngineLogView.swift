import SwiftUI

struct AIEngineLogView: View {
    @ObservedObject var viewModel: BoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ScrollViewReader { proxy in
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
                .onChange(of: viewModel.logEntries.count) {
                    withAnimation {
                        proxy.scrollTo("logEnd", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.showAllLogs) {
                    withAnimation {
                        proxy.scrollTo("logEnd", anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo("logEnd", anchor: .bottom)
                }
            }
            .padding(5)
            .background(Color.black.opacity(0.03))
            .cornerRadius(4)

            Toggle("Show All Logs".localized, isOn: $viewModel.showAllLogs)
                .font(.caption)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
    }
}
