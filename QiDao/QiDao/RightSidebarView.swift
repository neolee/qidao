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
                VStack(spacing: 0) {
                    if viewModel.isAnalyzing {
                        if let result = viewModel.analysisResult {
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
                .frame(height: 180)
            }

            GroupBox(label: Label("Evaluation".localized, systemImage: "eye")) {
                VStack(spacing: 15) {
                    if viewModel.isAnalyzing {
                        if let result = viewModel.analysisResult {
                            HStack {
                                Text("Score Lead".localized)
                                Spacer()
                                Text(String(format: "%+.1f", result.rootInfo.scoreLead))
                                    .bold()
                            }
                            .font(.subheadline)

                            // Ownership Map
                            if viewModel.config.display.showOwnership {
                                if let ownership = result.ownership {
                                    OwnershipMapView(ownership: ownership, size: Int(viewModel.board.getSize()))
                                        .aspectRatio(1.0, contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                        .cornerRadius(4)
                                } else {
                                    VStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Calculating Ownership...".localized)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            .font(.caption)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
                .padding(.vertical, 5)
                .frame(height: 220) // Fixed height for Evaluation section
            }
        }
        .padding()
        .frame(minWidth: 200, maxWidth: 300)
    }
}

struct OwnershipMapView: View {
    let ownership: [Double]
    let size: Int

    var body: some View {
        Canvas { context, geoSize in
            let cellSize = geoSize.width / CGFloat(size)

            for y in 0..<size {
                for x in 0..<size {
                    let idx = y * size + x
                    if idx < ownership.count {
                        let val = ownership[idx] // -1.0 to 1.0
                        let color: Color
                        if val > 0 {
                            color = Color.black.opacity(val * 0.8)
                        } else {
                            color = Color.white.opacity(-val * 0.8)
                        }

                        let rect = CGRect(
                            x: CGFloat(x) * cellSize,
                            y: CGFloat(y) * cellSize,
                            width: cellSize,
                            height: cellSize
                        )
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
        .background(Color.gray.opacity(0.2))
    }
}
