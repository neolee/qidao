import Foundation
import qidao_coreFFI

extension BoardViewModel {
    // MARK: - Turn Logic

    func isHumanTurn(for color: StoneColor) -> Bool {
        switch aiRole {
        case .manual: return true
        case .white: return color == .black
        case .black: return color == .white
        case .both: return false
        }
    }

    var isHumanTurn: Bool {
        isHumanTurn(for: nextColor)
    }

    var isAITurn: Bool {
        !isHumanTurn
    }

    // MARK: - Play Actions

    func startNewGame(size: Int, komi: Double, handicap: Int, timeSettings: PlayTimeSettings = PlayTimeSettings()) {
        aiManager.resetSession()
        gameManager.reset(size: size)
        let game = gameManager.getGame()
        var meta = game.getMetadata()

        if handicap > 0 {
            // For handicap games, komi is usually 0.5 in most systems to avoid draws.
            // In Chinese rules "还子" (returning stones), it's effectively 0.5 or 0.
            // We'll use 0.5 as a default for handicap games.
            meta.komi = 0.5
            meta.handicap = UInt32(handicap)
            game.setMetadata(metadata: meta)

            let stones = getHandicapStones(size: size, count: handicap)
            for (x, y) in stones {
                game.addStone(x: UInt32(x), y: UInt32(y), color: .black)
            }

            game.setNextPlayer(color: .white)
        } else {
            meta.komi = komi
            meta.handicap = 0
            game.setMetadata(metadata: meta)
            game.setNextPlayer(color: .black)
        }

        gameManager.syncState(rebuildTree: true)
        resetClock(settings: timeSettings)
    }

    func pass(isAI: Bool = false) {
        if appMode == .play && !isAI {
            guard isHumanTurn else { return }
        }

        try? gameManager.getGame().pass(color: nextColor)
        gameManager.syncState()
        updateClockOnMove()
        if isAnalyzing {
            updateAnalysis()
        }
    }

    func resign(isAI: Bool = false) {
        if appMode == .play && !isAI {
            guard isHumanTurn else { return }
        }

        let winner = nextColor == .black ? "White" : "Black"
        let currentMeta = gameManager.getGame().getMetadata()
        gameManager.getGame().setMetadata(metadata: GameMetadata(
            blackName: currentMeta.blackName,
            blackRank: currentMeta.blackRank,
            whiteName: currentMeta.whiteName,
            whiteRank: currentMeta.whiteRank,
            komi: currentMeta.komi,
            handicap: currentMeta.handicap,
            result: "\(winner.first!)+R",
            date: currentMeta.date,
            event: currentMeta.event,
            gameName: currentMeta.gameName,
            place: currentMeta.place,
            size: currentMeta.size
        ))
        gameManager.syncState()
        stopClock()
    }

    // MARK: - AI Play Logic

    func checkAIMove() {
        guard appMode == .play, isAnalyzing, aiStatus == .ready else { return }

        if isAITurn {
            let game = gameManager.getGame()
            let initialStones = game.getInitialStones()
            let moves = game.getAnalysisMoves()
            let nextPlayer = nextColor == .black ? "B" : "W"
            let initialPlayer = gameState.initialColor == .black ? "B" : "W"
            let currentMetadata = metadata
            let currentConfig = config
            let startNodeId = gameState.currentNodeId

            aiPlayTask?.cancel()
            aiPlayTask = Task {
                // Add a small delay to avoid immediate play during navigation
                // and give the UI time to settle.
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }

                let move = await aiManager.requestAIMove(
                    initialStones: initialStones,
                    moves: moves,
                    nextPlayer: nextPlayer,
                    initialPlayer: initialPlayer,
                    metadata: currentMetadata,
                    config: currentConfig,
                    timeSettings: playTimeSettings
                )

                if Task.isCancelled { return }

                // Re-check if we are still on the same node after AI finished thinking
                guard self.gameState.currentNodeId == startNodeId else {
                    self.aiManager.addLog("AI Play: Node changed from \(startNodeId) to \(self.gameState.currentNodeId), ignoring move", type: .play)
                    return
                }

                // Re-check conditions after async call
                guard self.isAnalyzing, self.appMode == .play else { return }

                if let move = move {
                    self.placeStone(x: move.x, y: move.y, isAI: true)
                } else {
                    // If AI returns nil, it could be a PASS or an error.
                    // For now we assume it's a PASS if the engine is still ready.
                    self.pass(isAI: true)
                }
            }
        }
    }

    // MARK: - Clock Logic

    func startClock() {
        guard appMode == .play, playTimeSettings.isEnabled else { return }
        if clockState == nil {
            clockState = PlayClockState(humanReserveRemaining: playTimeSettings.humanReserveTime)
        }

        // Only set start time if it's not the first move and not already set (for resuming)
        if moveCount > 0 && clockState?.currentMoveStartTime == nil {
            if isHumanTurn {
                clockState?.currentMoveStartTime = Date()
            }
        }

        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            if let strongSelf = self {
                Task { @MainActor in
                    strongSelf.tickClock()
                }
            }
        }
    }

    func stopClock() {
        if let startTime = clockState?.currentMoveStartTime {
            clockState?.elapsedTimeBeforePause += Date().timeIntervalSince(startTime)
            clockState?.currentMoveStartTime = nil
        }
        clockTimer?.invalidate()
        clockTimer = nil
    }

    func resetClock(settings: PlayTimeSettings) {
        self.playTimeSettings = settings
        if settings.isEnabled {
            clockState = PlayClockState(humanReserveRemaining: settings.humanReserveTime)
            if appMode == .play {
                startClock()
            }
        } else {
            clockState = nil
            stopClock()
        }
    }

    func tickClock() {
        guard var state = clockState, !state.isTimeout, appMode == .play else { return }

        if isHumanTurn && aiManager.aiStatus != .thinking {
            if let startTime = state.currentMoveStartTime {
                let elapsed = Date().timeIntervalSince(startTime) + state.elapsedTimeBeforePause
                let remainingInMove = playTimeSettings.humanSecondsPerMove - elapsed

                // Sound feedback for last 5 seconds
                if remainingInMove <= 5.0 && remainingInMove > 0 {
                    let second = Int(ceil(remainingInMove))
                    if second != state.lastBeepSecond {
                        state.lastBeepSecond = second
                        if playSound {
                            SoundManager.shared.playSystemBeep()
                        }
                    }
                }

                if remainingInMove < 0 {
                    let over = -remainingInMove
                    if over >= state.humanReserveRemaining {
                        state.humanReserveRemaining = 0
                        state.isTimeout = true
                        showTimeoutDialog = true
                        self.clockState = state
                        stopClock()
                        return
                    }
                }
            }
        }

        // Always update clockState to trigger UI refresh for the countdown
        self.clockState = state
    }

    func handleTimeout(endGame: Bool) {
        showTimeoutDialog = false
        if endGame {
            // Stop play mode logic but stay in the mode
            playTimeSettings.isEnabled = false
            aiRole = .manual
            clockState = nil
            stopClock()
        } else {
            // Continue in untimed mode
            playTimeSettings.isEnabled = false
            clockState = nil
            stopClock()
        }
    }

    func updateClockOnMove() {
        guard let state = clockState, playTimeSettings.isEnabled else { return }

        // If we have a startTime, it means someone just moved.
        if let startTime = state.currentMoveStartTime {
            let elapsed = Date().timeIntervalSince(startTime) + state.elapsedTimeBeforePause

            // We only deduct from reserve if it's human's turn
            let wasHumanTurn = isHumanTurn(for: nextColor.opponent)

            if wasHumanTurn && elapsed > playTimeSettings.humanSecondsPerMove {
                let over = elapsed - playTimeSettings.humanSecondsPerMove
                clockState?.humanReserveRemaining = max(0, state.humanReserveRemaining - over)
            }
        }

        // Reset move start time for the next player if it's human's turn
        if isHumanTurn {
            clockState?.currentMoveStartTime = Date()
        } else {
            clockState?.currentMoveStartTime = nil
        }
        clockState?.elapsedTimeBeforePause = 0
        clockState?.lastBeepSecond = -1
    }
}
