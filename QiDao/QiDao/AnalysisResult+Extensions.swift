import Foundation
import qidao_coreFFI

extension AnalysisMoveInfo {
    /// Compares two move infos based on winrate and visits.
    /// - Parameters:
    ///   - other: The other move info to compare with.
    ///   - isWhiteTurn: Whether it's currently White's turn to move.
    /// - Returns: True if this move is "better" than the other.
    func isBetter(than other: AnalysisMoveInfo, isWhiteTurn: Bool) -> Bool {
        if abs(self.winrate - other.winrate) > 0.001 {
            if isWhiteTurn {
                // For white turn, lower black winrate is better
                return self.winrate < other.winrate
            } else {
                // For black turn, higher black winrate is better
                return self.winrate > other.winrate
            }
        }
        // Tie-breaker: more visits
        return self.visits > other.visits
    }
}

extension Array where Element == AnalysisMoveInfo {
    /// Returns a sorted copy of the move infos based on winrate.
    func sortedByWinRate(isWhiteTurn: Bool) -> [AnalysisMoveInfo] {
        return self.sorted { $0.isBetter(than: $1, isWhiteTurn: isWhiteTurn) }
    }
}

extension AnalysisResult {
    /// Returns the move infos sorted by their winrate ranking.
    func sortedMoves(isWhiteTurn: Bool) -> [AnalysisMoveInfo] {
        return self.moveInfos.sortedByWinRate(isWhiteTurn: isWhiteTurn)
    }

    /// Returns the absolute best winrate found among all candidates.
    func bestWinRate(isWhiteTurn: Bool) -> Double? {
        if isWhiteTurn {
            return moveInfos.map { $0.winrate }.min()
        } else {
            return moveInfos.map { $0.winrate }.max()
        }
    }
}
