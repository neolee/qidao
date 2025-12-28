import SwiftUI

struct RightSidebarView: View {
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject private var langManager = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // 1. Variation Tree - Takes remaining space
            GroupBox(label: Label("Variation Tree".localized, systemImage: "arrow.triangle.branch")) {
                VariationTreeView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 2. Move Evaluation - Fixed height
            MoveEvaluationView(viewModel: viewModel)

            // 3. Evaluation Board - Square based on width
            EvaluationBoardView(
                viewModel: viewModel,
                ownership: viewModel.isAnalyzing ? viewModel.analysisResult?.ownership : nil,
                pv: viewModel.isAnalyzing ? viewModel.analysisResult?.moveInfos.sorted(by: { $0.visits > $1.visits }).first?.pv : nil
            )
        }
        .padding()
        .frame(minWidth: 250, maxWidth: 500)
    }
}
