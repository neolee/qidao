import Foundation
import qidao_coreFFI
import Combine

@MainActor
class AIManager: ObservableObject {
    @Published var isAnalyzing: Bool = false
    @Published var isEngineStarted: Bool = false
    @Published var aiStatus: AIStatus = .idle
    @Published var engineMessage: String = "AI Not Started".localized
    @Published var analysisResult: AnalysisResult? = nil
    @Published var logEntries: [EngineLog] = []
    @Published var showAllLogs: Bool = false {
        didSet {
            Task {
                await analysisEngine?.setLoggingEnabled(enabled: showAllLogs)
            }
            if !showAllLogs {
                self.logEntries.removeAll { $0.type == .raw }
            }
        }
    }
    @Published var winRateHistory: [Int: Double] = [:]
    @Published var scoreLeadHistory: [Int: Double] = [:]
    @Published var blunders: [Int: BoardViewModel.BlunderType] = [:]
    @Published var isFullGameScanning: Bool = false
    @Published var fullScanProgress: (completed: Int, total: Int) = (0, 0)
    var blunderThreshold: Double = 15.0

    var analysisEngine: AnalysisEngine? = nil
    var resultsById: [String: AnalysisResult] = [:]

    // Task Slots
    var playTask: Task<Void, Never>? = nil          // Slot A: Play
    var interactiveTask: Task<Void, Never>? = nil   // Slot B: Interactive Analysis
    var fullScanTask: Task<Void, Never>? = nil      // Slot C: Full Game Analysis

    // Infrastructure Tasks
    var resultTask: Task<Void, Never>? = nil
    var logTask: Task<Void, Never>? = nil

    @Published var isEngineReady: Bool = false
    var currentAnalysisId: String? = nil
    var analysisSessionId: Int = 0
    private var playCounter: Int = 0
    private var activeThinkingTasks: Int = 0
    var mainLineColors: [Int: String] = [:]
    var currentTurnColorIsWhite: Bool = false
    var currentTurnNumber: Int = 0
    var currentNodeId: String = ""
    var lastMainLineMoves: [[String]] = []

    func start(executable: String, args: [String], config: AIConfig) {
        guard analysisEngine == nil else { return }

        isAnalyzing = true
        aiStatus = .starting
        isEngineReady = false
        engineMessage = "Starting AI...".localized
        logEntries = []
        blunderThreshold = config.display.blunderThreshold

        Task {
            do {
                let engine = AnalysisEngine()
                await engine.setLoggingEnabled(enabled: self.showAllLogs)
                try await engine.start(executable: executable, args: args)
                self.analysisEngine = engine
                self.isEngineStarted = true
                // aiStatus stays .starting until we see the "ready" log in addLog
                self.startLogPolling()
                self.startResultPolling()
            } catch {
                self.isAnalyzing = false
                self.isEngineStarted = false
                self.aiStatus = .idle
                let errorMsg = String(format: "AI Error: %@".localized, error.localizedDescription)
                self.engineMessage = errorMsg
                self.addLog(errorMsg, isError: true)
            }
        }
    }

    func stop() {
        isAnalyzing = false
        isEngineStarted = false
        aiStatus = .idle
        isEngineReady = false
        analysisResult = nil
        winRateHistory = [:]
        scoreLeadHistory = [:]
        blunders = [:]

        playTask?.cancel()
        playTask = nil
        interactiveTask?.cancel()
        interactiveTask = nil
        fullScanTask?.cancel()
        fullScanTask = nil

        resultTask?.cancel()
        resultTask = nil
        logTask?.cancel()
        logTask = nil
        if let engine = analysisEngine {
            Task {
                try? await engine.stop()
            }
        }
        analysisEngine = nil
        engineMessage = "AI Not Started".localized
    }

    func updateAnalysis(
        currentNodeId: String,
        initialStones: [[String]],
        moves: [[String]],
        nextPlayer: String,
        initialPlayer: String,
        turnNumber: Int,
        metadata: GameMetadata,
        config: AIConfig
    ) {
        guard isAnalyzing, let engine = analysisEngine, aiStatus != .thinking else {
            if !isAnalyzing { analysisResult = nil }
            return
        }

        self.currentNodeId = currentNodeId
        self.currentTurnColorIsWhite = (nextPlayer == "W")
        self.currentTurnNumber = turnNumber
        self.blunderThreshold = config.display.blunderThreshold

        interactiveTask?.cancel()

        let analysisSettings = config.analysis
        let displaySettings = config.display

        interactiveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)

                if let oldId = self.currentAnalysisId {
                    try? await engine.terminate(id: oldId)
                }

                let newId = "qidao-\(self.analysisSessionId)-\(currentNodeId)"
                self.currentAnalysisId = newId

                let analyzeTurn = max(0, moves.count)

                var query: [String: Any] = [
                    "id": newId,
                    "moves": moves,
                    "initialStones": initialStones,
                    "initialPlayer": initialPlayer,
                    "rules": "chinese",
                    "komi": metadata.komi,
                    "boardXSize": metadata.size,
                    "boardYSize": metadata.size,
                    "analyzeTurns": [analyzeTurn],
                    "priority": 10,
                    "includeOwnership": displaySettings.showOwnership,
                    "includePolicy": analysisSettings.includePolicy
                ]

                if let reportInterval = analysisSettings.reportDuringSearchEvery, reportInterval >= 0.001 {
                    query["reportDuringSearchEvery"] = reportInterval
                }

                if let maxVisits = analysisSettings.maxVisits {
                    query["maxVisits"] = maxVisits
                }

                var overrideSettings: [String: Any] = [
                    "reportAnalysisWinratesAs": "BLACK"
                ]
                if let maxTime = analysisSettings.maxTime {
                    overrideSettings["maxTime"] = maxTime
                }

                for (key, value) in analysisSettings.advancedParams {
                    if let boolVal = Bool(value.lowercased()) {
                        overrideSettings[key] = boolVal
                    } else if let doubleVal = Double(value) {
                        overrideSettings[key] = doubleVal
                    } else {
                        overrideSettings[key] = value
                    }
                }

                if !overrideSettings.isEmpty {
                    query["overrideSettings"] = overrideSettings
                }

                let jsonData = try JSONSerialization.data(withJSONObject: query)
                let jsonString = String(data: jsonData, encoding: .utf8)!

                self.aiStatus = .analyzing
                self.engineMessage = "Analysis started".localized
                self.addEventLog("Analysis started".localized, type: .analysis)
                try await engine.analyze(queryJson: jsonString)
            } catch is CancellationError {
            } catch {
                self.addLog("Analysis error: \(error)", isError: true)
                self.aiStatus = .ready
            }
        }
    }

    func startFullGameAnalysis(
        mainLineMoves: [[String]],
        initialStones: [[String]],
        metadata: GameMetadata,
        config: AIConfig,
        initialPlayer: String
    ) {
        guard isAnalyzing, let engine = analysisEngine else { return }
        if mainLineMoves.isEmpty && initialStones.isEmpty { return }

        let hasChanged = mainLineMoves != lastMainLineMoves

        // If nothing changed and we are already scanning, just return
        if !hasChanged && isFullGameScanning {
            return
        }

        // Detect branch change and clear history for the changed part
        if hasChanged {
            var forkPoint = 0
            while forkPoint < mainLineMoves.count && forkPoint < lastMainLineMoves.count {
                if mainLineMoves[forkPoint] != lastMainLineMoves[forkPoint] {
                    break
                }
                forkPoint += 1
            }

            let maxTurn = max(mainLineMoves.count, lastMainLineMoves.count)
            if forkPoint <= maxTurn {
                for turn in forkPoint...maxTurn {
                    self.winRateHistory.removeValue(forKey: turn)
                    self.scoreLeadHistory.removeValue(forKey: turn)
                    self.blunders.removeValue(forKey: turn)
                }
            }
            self.lastMainLineMoves = mainLineMoves
        }

        // Check if there are actually any missing turns to analyze
        let totalTurns = mainLineMoves.count
        let missingTurns = (0...totalTurns).filter { self.winRateHistory[$0] == nil }
        if missingTurns.isEmpty {
            isFullGameScanning = false
            return
        }

        self.blunderThreshold = config.display.blunderThreshold
        self.mainLineColors = [:]
        for (i, m) in mainLineMoves.enumerated() {
            if m.count >= 1 {
                self.mainLineColors[i + 1] = m[0]
            }
        }

        fullScanTask?.cancel()
        isFullGameScanning = true
        let totalPositions = totalTurns + 1
        let alreadyAnalyzed = totalPositions - missingTurns.count
        fullScanProgress = (alreadyAnalyzed, totalPositions)
        self.addEventLog(String(format: "Full game analysis started: %d moves to analyze".localized, missingTurns.count), type: .fullScan)

        fullScanTask = Task {
            do {
                let scanId = "fullscan-\(self.analysisSessionId)"
                // Only terminate the previous full scan, not the current move analysis
                try? await engine.terminate(id: scanId)

                let batchSize = 10
                for startTurn in stride(from: 0, through: totalTurns, by: batchSize) {
                    if Task.isCancelled { break }

                    let endTurn = min(startTurn + batchSize - 1, totalTurns)
                    // Only analyze turns that don't have winrate data yet
                    let analyzeTurns = Array(startTurn...endTurn).filter { self.winRateHistory[$0] == nil }

                    if analyzeTurns.isEmpty { continue }

                    let query: [String: Any] = [
                        "id": scanId,
                        "initialStones": initialStones,
                        "moves": mainLineMoves,
                        "initialPlayer": initialPlayer,
                        "rules": "chinese",
                        "komi": metadata.komi,
                        "boardXSize": metadata.size,
                        "boardYSize": metadata.size,
                        "analyzeTurns": analyzeTurns,
                        "maxVisits": config.analysis.effectiveFullScanMaxVisits,
                        "priority": -10,
                        "includeOwnership": false,
                        "includePolicy": false,
                        "overrideSettings": [
                            "reportAnalysisWinratesAs": "BLACK",
                            "maxVisits": config.analysis.effectiveFullScanMaxVisits // Ensure it's also in overrideSettings
                        ]
                    ]

                    let jsonData = try JSONSerialization.data(withJSONObject: query)
                    let jsonString = String(data: jsonData, encoding: .utf8)!

                    try await engine.analyze(queryJson: jsonString)

                    // Wait for this batch to complete before sending next one
                    // to avoid overwhelming the engine's queue
                    var batchCompleted = false
                    var waitAttempts = 0
                    while !batchCompleted && waitAttempts < 60 { // 30s timeout per batch
                        if Task.isCancelled { break }

                        let allDone = analyzeTurns.allSatisfy { self.winRateHistory[$0] != nil }
                        if allDone {
                            batchCompleted = true
                        } else {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            waitAttempts += 1
                        }
                    }
                }

                if !Task.isCancelled {
                    let finalMsg = String(format: "Full game analysis progress: %d/%d moves".localized,
                                           self.fullScanProgress.total,
                                           self.fullScanProgress.total)
                    self.addEventLog(finalMsg, type: .fullScan)
                    self.addEventLog("Full game analysis completed".localized, type: .fullScan)
                }
            } catch {
                self.addLog("Full game analysis failed: \(error)", isError: true)
            }
            isFullGameScanning = false
        }
    }

    func stopFullGameAnalysis() {
        fullScanTask?.cancel()
        fullScanTask = nil
        isFullGameScanning = false
    }

    func clearAnalysisResult() {
        interactiveTask?.cancel()
        stopFullGameAnalysis()
        currentAnalysisId = nil
        self.analysisResult = nil
        if isEngineReady && aiStatus == .analyzing {
            aiStatus = .ready
            engineMessage = "AI Engine Ready".localized
        }
    }

    func cancelPlay() {
        if aiStatus == .thinking {
            aiStatus = .ready
            engineMessage = "AI Engine Ready".localized
        }
    }

    func requestAIMove(
        initialStones: [[String]],
        moves: [[String]],
        nextPlayer: String,
        initialPlayer: String,
        metadata: GameMetadata,
        config: AIConfig,
        timeSettings: PlayTimeSettings? = nil
    ) async -> (x: Int, y: Int)? {
        guard isAnalyzing, let engine = analysisEngine else {
            self.addLog("AI Play: Engine not ready or analysis disabled", type: .play)
            return nil
        }

        // Cancel analysis tasks to focus on thinking
        interactiveTask?.cancel()
        stopFullGameAnalysis()

        activeThinkingTasks += 1
        aiStatus = .thinking
        engineMessage = "AI is thinking...".localized
        addEventLog("\("AI is thinking...".localized) (\(nextPlayer))", type: .play)

        defer {
            activeThinkingTasks -= 1
            if activeThinkingTasks <= 0 {
                activeThinkingTasks = 0
                aiStatus = .ready
            }
        }

        playCounter += 1
        let playId = "play-\(self.analysisSessionId)-\(moves.count)-\(playCounter)"
        let reqMsg = String(format: "Requesting AI move (%@, %d)".localized, nextPlayer, moves.count)
        self.addLog("\(reqMsg) [id: \(playId)]", type: .play)

        do {
            // Terminate any previous play or analysis to free GPU
            try? await engine.terminate(id: playId)
            if let oldId = self.currentAnalysisId {
                try? await engine.terminate(id: oldId)
            }
            // Also try to terminate any other play IDs just in case
            try? await engine.terminate(id: "play-\(self.analysisSessionId)-\(moves.count - 1)")
            try? await engine.terminate(id: "fullscan-\(self.analysisSessionId)")

            var maxVisits = config.analysis.maxVisits ?? 1000
            var maxTime = config.analysis.maxTime

            if let settings = timeSettings, settings.isEnabled {
                switch settings.aiLimitType {
                case .global:
                    // Already initialized with global config
                    break
                case .visits:
                    maxVisits = Int(settings.aiLimitValue)
                    maxTime = nil // Priority to visits
                case .time:
                    maxTime = settings.aiLimitValue
                }
            }

            var overrideSettings: [String: Any] = [
                "reportAnalysisWinratesAs": "BLACK"
            ]
            if let time = maxTime {
                overrideSettings["maxTime"] = time
            }

            let query: [String: Any] = [
                "id": playId,
                "initialStones": initialStones,
                "moves": moves,
                "initialPlayer": initialPlayer,
                "rules": "chinese",
                "komi": metadata.komi,
                "boardXSize": metadata.size,
                "boardYSize": metadata.size,
                "analyzeTurns": [moves.count],
                "maxVisits": maxVisits,
                "priority": 100, // Highest priority
                "overrideSettings": overrideSettings
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: query)
            let jsonString = String(data: jsonData, encoding: .utf8)!

            // Clear previous results for this ID
            self.resultsById.removeValue(forKey: playId)

            try await engine.analyze(queryJson: jsonString)

            // Wait for the result of this specific ID
            let checkInterval: UInt64 = 50_000_000 // 0.05s
            var attempts = 0
            while attempts < 6000 { // 5 minutes timeout
                if Task.isCancelled {
                    try? await engine.terminate(id: playId)
                    return nil
                }
                if let result = self.resultsById[playId] {
                    // We want the final result (isDuringSearch == false)
                    // or at least one with enough visits if it's taking too long
                    if !result.isDuringSearch || (attempts > 100 && result.rootInfo.visits > 10) {
                        if let bestMoveStr = result.moveInfos.first?.moveStr {
                            let foundMsg = String(format: "Found AI move %@".localized, bestMoveStr)
                            self.addLog("\(foundMsg) [id: \(playId)]", type: .play)
                            if let coords = decodeKataGoMove(bestMoveStr, size: Int(metadata.size)) {
                                self.engineMessage = "\("AI played".localized) \(bestMoveStr)"
                                self.addEventLog("\("AI played".localized) \(bestMoveStr)", type: .play)
                                return coords
                            } else if bestMoveStr.uppercased() == "PASS" {
                                self.addLog("AI Play: AI passed for ID \(playId)", type: .play)
                                self.engineMessage = "AI passed".localized
                                self.addEventLog("AI passed".localized, type: .play)
                                return nil
                            }
                        }
                    }
                }
                try await Task.sleep(nanoseconds: checkInterval)
                attempts += 1
            }
            self.addLog("AI Play: Timeout or no move found for ID \(playId)", type: .play, isError: true)
            return nil
        } catch is CancellationError {
            self.engineMessage = "AI Thinking Cancelled".localized
            self.addEventLog("AI Thinking Cancelled".localized, type: .play)
            return nil
        } catch {
            self.addLog("AI Play error: \(error)", type: .play, isError: true)
            return nil
        }
    }

    private func decodeKataGoMove(_ move: String, size: Int) -> (x: Int, y: Int)? {
        let move = move.uppercased()
        if move == "PASS" { return nil }
        guard move.count >= 2 else { return nil }

        let colChar = move.first!
        let rowStr = move.dropFirst()

        guard let row = Int(rowStr) else { return nil }

        let colMap: [Character: Int] = [
            "A": 0, "B": 1, "C": 2, "D": 3, "E": 4, "F": 5, "G": 6, "H": 7,
            "J": 8, "K": 9, "L": 10, "M": 11, "N": 12, "O": 13, "P": 14, "Q": 15,
            "R": 16, "S": 17, "T": 18
        ]

        guard let x = colMap[colChar] else { return nil }
        let y = size - row

        return (x, y)
    }

    func resetSession() {
        self.analysisSessionId += 1
        self.playCounter = 0
        self.winRateHistory = [:]
        self.scoreLeadHistory = [:]
        self.blunders = [:]
        self.analysisResult = nil
        self.resultsById = [:]
        self.lastMainLineMoves = []
        if isAnalyzing {
            Task {
                try? await analysisEngine?.terminateAll()
            }
        }
    }

    func setMainLineColors(_ colors: [Int: String]) {
        self.mainLineColors = colors
    }
}
