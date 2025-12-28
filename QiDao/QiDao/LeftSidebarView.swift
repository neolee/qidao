import SwiftUI
import qidao_coreFFI

struct LeftSidebarView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Binding var showInfoEditor: Bool
    @Binding var showAIConfig: Bool
    @ObservedObject private var langManager = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            GameInfoView(viewModel: viewModel, showInfoEditor: $showInfoEditor)

            WinRateView(viewModel: viewModel)

            AIEngineView(viewModel: viewModel, showAIConfig: $showAIConfig)
        }
        .padding()
        .frame(minWidth: 250, maxWidth: 350)
    }
}
