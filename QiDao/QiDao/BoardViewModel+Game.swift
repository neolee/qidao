import Foundation
import qidao_coreFFI

extension BoardViewModel {
    func resetBoard() {
        aiManager.resetSession()
        gameManager.reset(size: boardSize)
    }

    func changeBoardSize(_ newSize: Int) {
        guard !isSizeLocked else { return }
        UserDefaults.standard.set(newSize, forKey: "boardSize")
        resetBoard()
    }

    func updateMetadata(_ newMetadata: GameMetadata) {
        gameManager.updateMetadata(newMetadata)
    }

    func updateNodeComment(_ comment: String) {
        gameManager.getGame().setComment(comment: comment)
        gameManager.syncState()
    }

    func loadSgf(url: URL) {
        do {
            let newGame = try sgfManager.loadSgf(url: url)
            gameManager.setGame(newGame)
            aiManager.resetSession()

            // Update main line colors for win rate normalization
            let mainLine = newGame.getMainLineMoves()
            var colors: [Int: String] = [:]
            for (i, m) in mainLine.enumerated() {
                if m.count >= 1 {
                    colors[i + 1] = m[0]
                }
            }
            aiManager.setMainLineColors(colors)

            if isAnalyzing {
                // Use the newGame's data directly to avoid stale metadata from self.metadata
                let initialPlayer = newGame.getNextColor() == .black ? "B" : "W"
                aiManager.startFullGameAnalysis(
                    mainLineMoves: newGame.getMainLineMoves(),
                    initialStones: newGame.getInitialStones(),
                    metadata: newGame.getMetadata(),
                    config: config,
                    initialPlayer: initialPlayer
                )
            }
        } catch {
            aiManager.addLog("\("Load Failed".localized): \(error.localizedDescription)", isError: true)
        }
    }

    func saveSgf(url: URL) {
        do {
            try sgfManager.saveSgf(game: gameManager.getGame(), url: url)
        } catch {
            aiManager.addLog("\("Save Failed".localized): \(error.localizedDescription)", isError: true)
        }
    }
}
