import Foundation
import qidao_coreFFI

extension AIManager {
    func startResultPolling() {
        resultTask?.cancel()
        resultTask = Task {
            while !Task.isCancelled {
                guard let engine = analysisEngine else {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    continue
                }

                do {
                    let result = try await engine.getNextResult()
                    if Task.isCancelled { break }
                    self.handleAnalysisResult(result)
                } catch {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            }
        }
    }

    func handleAnalysisResult(_ result: AnalysisResult) {
        if result.noResults { return }

        // Store result by ID for requestAIMove to find
        self.resultsById[result.id] = result

        let parts = result.id.split(separator: "-")
        if result.id.hasPrefix("qidao-") || result.id.hasPrefix("fullscan-") || result.id.hasPrefix("play-") {
            if parts.count >= 2, let resultSessionId = Int(parts[1]) {
                if resultSessionId != self.analysisSessionId { return }
            }
        }

        if result.id.hasPrefix("qidao-") {
            if result.id == currentAnalysisId && result.id.hasSuffix("-\(currentNodeId)") {
                let normalizedWinRate = WinRateConverter.convertWinRate(
                    result.rootInfo.winrate,
                    reportedAs: .black,
                    target: .black,
                    isWhiteTurn: currentTurnColorIsWhite
                )
                let normalizedScoreLead = WinRateConverter.convertScoreLead(
                    result.rootInfo.scoreLead,
                    reportedAs: .black,
                    target: .black,
                    isWhiteTurn: currentTurnColorIsWhite
                )

                let normalizedResult = AnalysisResult(
                    id: result.id,
                    turnNumber: result.turnNumber,
                    isDuringSearch: result.isDuringSearch,
                    noResults: result.noResults,
                    rootInfo: AnalysisRootInfo(
                        winrate: normalizedWinRate,
                        scoreLead: normalizedScoreLead,
                        visits: result.rootInfo.visits
                    ),
                    moveInfos: result.moveInfos,
                    ownership: result.ownership
                )

                self.analysisResult = normalizedResult
                self.winRateHistory[currentTurnNumber] = normalizedWinRate
                self.scoreLeadHistory[currentTurnNumber] = normalizedScoreLead
                detectBlunder(at: currentTurnNumber)

                if result.isDuringSearch {
                    self.engineMessage = "\("Visits".localized): \(result.rootInfo.visits)"
                } else {
                    let msg = "\("Analysis completed".localized) (\(result.rootInfo.visits) \("Visits".localized))"
                    self.engineMessage = msg
                    self.addEventLog(msg, type: .info)
                }
            }
        } else if result.id.hasPrefix("fullscan-") {
            if isFullGameScanning && !result.isDuringSearch {
                let turn = Int(result.turnNumber)
                let isWhiteNext = (turn == 0) ? false : (self.mainLineColors[turn + 1] == "W")

                let normalizedWinRate = WinRateConverter.convertWinRate(
                    result.rootInfo.winrate,
                    reportedAs: .black,
                    target: .black,
                    isWhiteTurn: isWhiteNext
                )
                let normalizedScoreLead = WinRateConverter.convertScoreLead(
                    result.rootInfo.scoreLead,
                    reportedAs: .black,
                    target: .black,
                    isWhiteTurn: isWhiteNext
                )

                self.winRateHistory[turn] = normalizedWinRate
                self.scoreLeadHistory[turn] = normalizedScoreLead
                detectBlunder(at: turn)
            }
        }
    }

    func detectBlunder(at turn: Int) {
        guard turn > 0,
              let currentWR = winRateHistory[turn],
              let prevWR = winRateHistory[turn - 1] else { return }

        let diff = currentWR - prevWR
        let absDiff = abs(diff)

        if absDiff >= blunderThreshold {
            blunders[turn] = .blunder
        } else {
            blunders.removeValue(forKey: turn)
        }
    }
}
