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
    var blunderThreshold: Double = 15.0

    private var analysisEngine: AnalysisEngine? = nil
    private var resultsById: [String: AnalysisResult] = [:]

    // Task Slots
    private var playTask: Task<Void, Never>? = nil          // Slot A: Play
    private var interactiveTask: Task<Void, Never>? = nil   // Slot B: Interactive Analysis
    private var fullScanTask: Task<Void, Never>? = nil      // Slot C: Full Game Analysis

    // Infrastructure Tasks
    private var resultTask: Task<Void, Never>? = nil
    private var logTask: Task<Void, Never>? = nil

    private var isEngineReady: Bool = false
    private var currentAnalysisId: String? = nil
    private var analysisSessionId: Int = 0
    private var mainLineColors: [Int: String] = [:]
    private var currentTurnColorIsWhite: Bool = false
    private var currentTurnNumber: Int = 0
    private var currentNodeId: String = ""
    private var lastMainLineMoves: [[String]] = []

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
                self.aiStatus = .ready
                self.startLogPolling()
                self.startResultPolling()
            } catch {
                self.isAnalyzing = false
                self.isEngineStarted = false
                self.aiStatus = .idle
                self.engineMessage = "AI Error: \(error)".localized
                self.addLog("AI Error: \(error)", isError: true)
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
        nextPlayer: String,
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

                var query: [String: Any] = [
                    "id": newId,
                    "moves": [] as [Any],
                    "initialStones": initialStones,
                    "initialPlayer": nextPlayer,
                    "rules": "chinese",
                    "komi": metadata.komi,
                    "boardXSize": metadata.size,
                    "boardYSize": metadata.size,
                    "analyzeTurns": [0],
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
                self.addEventLog("Analysis started".localized, type: .info)
                try await engine.analyze(queryJson: jsonString)
            } catch is CancellationError {
            } catch {
                print("Analysis error: \(error)")
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
                        "maxVisits": 40,
                        "priority": -10,
                        "includeOwnership": false,
                        "includePolicy": false,
                        "overrideSettings": [
                            "reportAnalysisWinratesAs": "BLACK"
                        ]
                    ]

                    let jsonData = try JSONSerialization.data(withJSONObject: query)
                    let jsonString = String(data: jsonData, encoding: .utf8)!

                    try await engine.analyze(queryJson: jsonString)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            } catch {
                print("Full game analysis failed: \(error)")
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
    }

    func requestAIMove(
        initialStones: [[String]],
        moves: [[String]],
        nextPlayer: String,
        initialPlayer: String,
        metadata: GameMetadata,
        config: AIConfig
    ) async -> (x: Int, y: Int)? {
        guard isAnalyzing, let engine = analysisEngine else {
            print("AI Play: Engine not ready or analysis disabled")
            return nil
        }

        // Cancel analysis tasks to focus on thinking
        interactiveTask?.cancel()
        stopFullGameAnalysis()

        aiStatus = .thinking
        engineMessage = "AI is thinking...".localized
        addEventLog("\("AI is thinking...".localized) (\(nextPlayer))", type: .ai)

        let playId = "play-\(self.analysisSessionId)-\(moves.count)"
        print("AI Play: Requesting move for \(nextPlayer), turn \(moves.count), ID \(playId)")

        do {
            // Terminate any previous play or analysis to free GPU
            try? await engine.terminate(id: playId)
            if let oldId = self.currentAnalysisId {
                try? await engine.terminate(id: oldId)
            }
            // Also try to terminate any other play IDs just in case
            try? await engine.terminate(id: "play-\(self.analysisSessionId)-\(moves.count - 1)")
            try? await engine.terminate(id: "fullscan-\(self.analysisSessionId)")

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
                "maxVisits": config.analysis.maxVisits ?? 1000,
                "priority": 100, // Highest priority
                "overrideSettings": [
                    "reportAnalysisWinratesAs": "BLACK"
                ]
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: query)
            let jsonString = String(data: jsonData, encoding: .utf8)!

            // Clear previous results for this ID
            self.resultsById.removeValue(forKey: playId)

            try await engine.analyze(queryJson: jsonString)

            // Wait for the result of this specific ID
            let checkInterval: UInt64 = 50_000_000 // 0.05s
            var attempts = 0
            while attempts < 400 { // 20 seconds timeout
                if Task.isCancelled {
                    self.aiStatus = .ready
                    return nil
                }
                if let result = self.resultsById[playId] {
                    // We want the final result (isDuringSearch == false)
                    // or at least one with enough visits if it's taking too long
                    if !result.isDuringSearch || (attempts > 100 && result.rootInfo.visits > 10) {
                        if let bestMoveStr = result.moveInfos.first?.moveStr {
                            print("AI Play: Found move \(bestMoveStr) for ID \(playId) after \(attempts) attempts")
                            if let coords = decodeKataGoMove(bestMoveStr, size: Int(metadata.size)) {
                                self.aiStatus = .ready
                                self.engineMessage = "\("AI played".localized) \(bestMoveStr)"
                                self.addEventLog("\("AI played".localized) \(bestMoveStr)", type: .ai)
                                return coords
                            } else if bestMoveStr.uppercased() == "PASS" {
                                print("AI Play: AI passed for ID \(playId)")
                                self.aiStatus = .ready
                                self.engineMessage = "AI passed".localized
                                self.addEventLog("AI passed".localized, type: .ai)
                                return nil
                            }
                        }
                    }
                }
                try await Task.sleep(nanoseconds: checkInterval)
                attempts += 1
            }
            print("AI Play: Timeout or no move found for ID \(playId)")
            self.aiStatus = .ready
            return nil
        } catch is CancellationError {
            self.aiStatus = .ready
            self.engineMessage = "AI Thinking Cancelled".localized
            self.addEventLog("AI Thinking Cancelled".localized, type: .info)
            return nil
        } catch {
            print("AI Play error: \(error)")
            aiStatus = .ready
            return nil
        }
    }

    private func decodeKataGoMove(_ move: String, size: Int) -> (x: Int, y: Int)? {
        let move = move.uppercased()
        if move == "PASS" { return nil } // TODO: Handle pass
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

    func addEventLog(_ message: String, type: LogType) {
        let entry = EngineLog(message: message, type: type)
        logEntries.append(entry)
        if logEntries.count > 1000 {
            logEntries.removeFirst(200)
        }
    }

    private func addLog(_ message: String, isError: Bool = false) {
        var displayMessage = message
        if message.hasPrefix("[STDERR] ") {
            displayMessage = String(message.dropFirst(9))
        } else if message.hasPrefix("[STDERR]") {
            displayMessage = String(message.dropFirst(8))
        }

        let trimmed = displayMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }

        let isComm = trimmed.hasPrefix(">>>") || trimmed.hasPrefix("<<<")
        if isComm && !showAllLogs { return }

        let lowerTrimmed = trimmed.lowercased()
        let containsErrorMarker = lowerTrimmed.contains("[error]") ||
                                 lowerTrimmed.contains("fatal error") ||
                                 lowerTrimmed.hasPrefix("error:") ||
                                 lowerTrimmed.contains(" error: ")

        let finalIsError = isError || containsErrorMarker
        let type: LogType = finalIsError ? .error : (isComm ? .raw : .info)
        let entry = EngineLog(message: trimmed, type: type)

        self.logEntries.append(entry)
        if self.logEntries.count > 2000 {
            self.logEntries.removeFirst(500)
        }

        if trimmed.contains("Started, ready to begin handling requests") {
            if !self.isEngineReady {
                self.isEngineReady = true
                self.engineMessage = "AI Started".localized
                self.addEventLog("AI Engine Ready", type: .info)
            }
        } else if trimmed.contains("info: visits") {
            self.isEngineReady = true
            self.engineMessage = trimmed
        } else if self.isEngineReady && !isComm && !finalIsError {
            self.engineMessage = trimmed
        } else if finalIsError {
            self.engineMessage = "AI Error".localized + ": " + trimmed
        }
    }

    private func startLogPolling() {
        logTask?.cancel()
        logTask = Task {
            while !Task.isCancelled {
                if let engine = analysisEngine {
                    let logs = await engine.getLogs()
                    for log in logs {
                        self.addLog(log)
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func startResultPolling() {
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

    private func handleAnalysisResult(_ result: AnalysisResult) {
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
            }
        } else if result.id.hasPrefix("fullscan-") {
            if isFullGameScanning && !result.isDuringSearch {
                let turn = Int(result.turnNumber)
                // We use .black perspective for history, so isWhiteTurn is not strictly needed
                // for the conversion if reportedAs and target are both .black.
                // But for correctness, we calculate it:
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

    private func detectBlunder(at turn: Int) {
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
