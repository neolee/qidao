import SwiftUI

struct MoveEvaluationView: View {
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject private var langManager = LanguageManager.shared

    var body: some View {
        GroupBox(label: Label("Move Evaluation".localized, systemImage: "list.bullet.rectangle")) {
            VStack(spacing: 0) {
                if viewModel.isAnalyzing {
                    if let result = viewModel.analysisResult {
                        let isStale = !result.id.hasSuffix("-\(viewModel.currentNodeId)")

                        // Header
                        HStack {
                            Text("Move_Header".localized).frame(width: 45, alignment: .leading)
                            Text("Win %".localized).frame(maxWidth: .infinity, alignment: .trailing)
                            Text("Lead".localized).frame(maxWidth: .infinity, alignment: .trailing)
                            Text("Visits".localized).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)

                        Divider()

                        let isWhiteTurn = viewModel.nextColor == .white

                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(result.moveInfos.sorted(by: { $0.visits > $1.visits }), id: \.moveStr) { info in
                                    let displayWinRate = WinRateConverter.convertWinRate(
                                        info.winrate,
                                        reportedAs: .black,
                                        target: .black,
                                        isWhiteTurn: isWhiteTurn
                                    )
                                    let displayScoreLead = WinRateConverter.convertScoreLead(
                                        info.scoreLead,
                                        reportedAs: .black,
                                        target: .black,
                                        isWhiteTurn: isWhiteTurn
                                    )
                                    HStack {
                                        Text(info.moveStr)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(width: 45, alignment: .leading)

                                        Text(String(format: "%.1f", displayWinRate * 100))
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                            .foregroundColor(displayWinRate > 0.5 ? .blue : .red)

                                        Text(String(format: "%+.1f", displayScoreLead))
                                            .frame(maxWidth: .infinity, alignment: .trailing)

                                        Text("\(info.visits)")
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                            .foregroundColor(.secondary)
                                    }
                                    .font(.system(size: 12))
                                    .padding(.vertical, 6)

                                    Divider()
                                }
                            }
                        }
                        .opacity(isStale ? 0.5 : 1.0)
                        .overlay(alignment: .center) {
                            if isStale {
                                CustomSpinner()
                            }
                        }
                    } else {
                        VStack {
                            CustomSpinner()
                            Text("Waiting for AI...".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    Text("AI Analysis Inactive".localized)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(height: 200) // Fixed height for move evaluation
        }
    }
}
