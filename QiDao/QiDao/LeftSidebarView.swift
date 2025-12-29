import SwiftUI
import qidao_coreFFI

struct LeftSidebarView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Binding var showInfoEditor: Bool
    @Binding var showAIConfig: Bool
    @ObservedObject private var langManager = LanguageManager.shared
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            GameInfoView(viewModel: viewModel, showInfoEditor: $showInfoEditor)

            switch viewModel.appMode {
            case .analysis:
                WinRateView(viewModel: viewModel)

                AIEngineView(viewModel: viewModel, showAIConfig: $showAIConfig)

                VStack(spacing: 10) {
                    Picker("", selection: $selectedTab) {
                        Text("Comments".localized).tag(0)
                        Text("AI Engine Logs".localized).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if selectedTab == 0 {
                        GameCommentView(viewModel: viewModel)
                    } else {
                        AIEngineLogView(viewModel: viewModel)
                    }
                }
                .frame(maxHeight: .infinity)

            case .edit:
                EditToolboxView(viewModel: viewModel)

                GameCommentView(viewModel: viewModel)
                    .frame(maxHeight: .infinity)

            case .play:
                PlayControlView(viewModel: viewModel)
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 250, maxWidth: 350)
    }
}
