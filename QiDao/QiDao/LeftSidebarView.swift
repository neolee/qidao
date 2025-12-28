import SwiftUI
import qidao_coreFFI

struct LeftSidebarView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Binding var showInfoEditor: Bool
    @Binding var showEngineConfig: Bool
    @ObservedObject private var langManager = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            GameInfoView(viewModel: viewModel, showInfoEditor: $showInfoEditor)

            WinRateView(viewModel: viewModel)

            AIEngineView(viewModel: viewModel, showEngineConfig: $showEngineConfig)
        }
        .padding()
        .frame(minWidth: 250, maxWidth: 350)
    }
}
