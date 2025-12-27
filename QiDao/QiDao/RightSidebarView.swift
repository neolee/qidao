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
                VStack(spacing: 10) {
                    if viewModel.isAnalyzing {
                        if let result = viewModel.analysisResult {
                            // Mini Board for Evaluation
                            EvaluationBoardView(
                                viewModel: viewModel,
                                ownership: result.ownership,
                                pv: result.moveInfos.sorted(by: { $0.visits > $1.visits }).first?.pv
                            )
                            .aspectRatio(1.0, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .background(viewModel.theme.boardColor)
                            .cornerRadius(4)
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
                .frame(height: 260) // Increased height for the mini board
            }
        }
        .padding()
        .frame(minWidth: 200, maxWidth: 300)
    }
}

struct EvaluationBoardView: View {
    @ObservedObject var viewModel: BoardViewModel
    let ownership: [Double]?
    let pv: [String]?
    let gridSize: Int = 19

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let spacing = size / CGFloat(gridSize + 1)

            ZStack {
                // 1. Ownership Map (Grayscale)
                if let ownership = ownership {
                    Canvas { context, geoSize in
                        let cellSize = geoSize.width / CGFloat(gridSize + 1)
                        let d = cellSize * 0.5
                        for y in 0..<gridSize {
                            for x in 0..<gridSize {
                                let idx = y * gridSize + x
                                if idx < ownership.count {
                                    let val = ownership[idx] // -1.0 to 1.0
                                    let probBlack = (val + 1.0) / 2.0
                                    let color = Color(white: 1.0 - probBlack)

                                    let rect = CGRect(
                                        x: CGFloat(x + 1) * cellSize - d/2,
                                        y: CGFloat(y + 1) * cellSize - d/2,
                                        width: d,
                                        height: d
                                    )
                                    context.fill(Path(rect), with: .color(color))
                                }
                            }
                        }
                    }
                }

                // 2. Grid & Star Points
                BoardGrid(gridSize: gridSize)
                    .stroke(viewModel.theme.lineColor.opacity(0.4), lineWidth: 0.5)

                StarPoints(gridSize: gridSize)
                    .fill(viewModel.theme.starPointColor.opacity(0.4))

                // 3. Current Stones
                ForEach(0..<gridSize, id: \.self) { y in
                    ForEach(0..<gridSize, id: \.self) { x in
                        if let color = viewModel.board.getStone(x: UInt32(x), y: UInt32(y)) {
                            StoneView(
                                color: color,
                                theme: viewModel.theme,
                                size: spacing * 0.85,
                                moveNumber: nil,
                                markerType: nil
                            )
                            .position(
                                x: CGFloat(x + 1) * spacing,
                                y: CGFloat(y + 1) * spacing
                            )
                        }
                    }
                }

                // 4. PV Sequence
                if let pv = pv {
                    let nextColor = viewModel.nextColor
                    ForEach(Array(pv.enumerated()), id: \.offset) { index, moveStr in
                        if let pos = viewModel.decodeKataGoMove(moveStr) {
                            let stoneColor: StoneColor = (index % 2 == 0) ? nextColor : (nextColor == .black ? .white : .black)
                            StoneView(
                                color: stoneColor,
                                theme: viewModel.theme,
                                size: spacing * 0.85,
                                moveNumber: index + 1,
                                markerType: nil,
                                fontSize: spacing * 0.6 // Larger font ratio for mini board
                            )
                            .position(
                                x: CGFloat(pos.x + 1) * spacing,
                                y: CGFloat(pos.y + 1) * spacing
                            )
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}
