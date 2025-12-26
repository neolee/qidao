import SwiftUI

struct RightSidebarView: View {
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject private var langManager = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label("Variation Tree".localized, systemImage: "arrow.triangle.branch")) {
                VariationTreeView(viewModel: viewModel)
                    .frame(maxHeight: .infinity)
            }

            GroupBox(label: Label("Move Evaluation".localized, systemImage: "list.bullet.rectangle")) {
                if let result = viewModel.analysisResult {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Move".localized).frame(width: 45, alignment: .leading)
                            Text("Win %".localized).frame(maxWidth: .infinity, alignment: .trailing)
                            Text("Lead".localized).frame(maxWidth: .infinity, alignment: .trailing)
                            Text("Visits".localized).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)

                        Divider()

                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(result.moveInfos.sorted(by: { $0.visits > $1.visits }), id: \.moveStr) { info in
                                    HStack {
                                        Text(info.moveStr)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(width: 45, alignment: .leading)

                                        Text(String(format: "%.1f", info.winrate * 100))
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                            .foregroundColor(info.winrate > 0.5 ? .blue : .red)

                                        Text(String(format: "%+.1f", info.scoreLead))
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
                    }
                    .frame(height: 180)
                } else {
                    Text("AI Analysis Inactive".localized)
                        .foregroundColor(.secondary)
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                }
            }

            GroupBox(label: Label("Evaluation".localized, systemImage: "eye")) {
                VStack(spacing: 15) {
                    if let result = viewModel.analysisResult {
                        HStack {
                            Text("Score Lead".localized)
                            Spacer()
                            Text(String(format: "%+.1f", result.rootInfo.scoreLead))
                                .bold()
                        }
                        .font(.subheadline)
                    } else {
                        Text("No Data".localized)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }

                    // Ownership Map Placeholder (Square)
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.05))

                        Text("Ownership Map".localized)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .aspectRatio(1.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 5)
            }
        }
        .padding()
        .frame(minWidth: 200, maxWidth: 300)
    }
}
