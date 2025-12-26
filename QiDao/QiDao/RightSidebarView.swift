import SwiftUI

struct RightSidebarView: View {
    @ObservedObject var viewModel: BoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Label("Variation Tree".localized, systemImage: "arrow.triangle.branch")) {
                VariationTreeView(viewModel: viewModel)
                    .frame(maxHeight: .infinity)
            }

            GroupBox(label: Label("Move Evaluation".localized, systemImage: "list.bullet.rectangle")) {
                if let result = viewModel.analysisResult {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(result.moveInfos.sorted(by: { $0.visits > $1.visits }), id: \.moveStr) { info in
                                HStack {
                                    Text(info.moveStr)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 40, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 4) {
                                        // Custom Win Rate Bar to avoid ProgressView layout bugs on macOS
                                        GeometryReader { barGeo in
                                            ZStack(alignment: .leading) {
                                                Capsule()
                                                    .fill(Color.secondary.opacity(0.2))
                                                Capsule()
                                                    .fill(info.winrate > 0.5 ? Color.blue : Color.red)
                                                    .frame(width: barGeo.size.width * CGFloat(info.winrate))
                                            }
                                        }
                                        .frame(height: 4)

                                        HStack {
                                            Text(String(format: "%.1f%%", info.winrate * 100))
                                            Spacer()
                                            Text(String(format: "%+.1f", info.scoreLead))
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
                                }
                                Divider()
                            }
                        }
                    }
                    .frame(height: 200)
                } else {
                    Text("AI Analysis Inactive".localized)
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                }
            }

            GroupBox(label: Label("Evaluation".localized, systemImage: "eye")) {
                if let result = viewModel.analysisResult {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Win Rate".localized)
                            Spacer()
                            Text(String(format: "%.1f%%", result.rootInfo.winrate * 100))
                                .bold()
                        }

                        // Win rate bar
                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                Color.blue
                                    .frame(width: geo.size.width * CGFloat(result.rootInfo.winrate))
                                Color.red
                                    .frame(width: geo.size.width * CGFloat(1.0 - result.rootInfo.winrate))
                            }
                        }
                        .frame(height: 20)
                        .cornerRadius(4)

                        HStack {
                            Text("Score Lead".localized)
                            Spacer()
                            Text(String(format: "%+.1f", result.rootInfo.scoreLead))
                                .bold()
                        }
                    }
                    .padding(.vertical, 5)
                } else {
                    Text("No Data".localized)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .frame(minWidth: 200, maxWidth: 300)
    }
}
