import Foundation
import qidao_coreFFI
import Combine

@MainActor
class AIManager: ObservableObject {
    @Published var isAnalyzing: Bool = false
    @Published var isEngineStarted: Bool = false
    @Published var engineMessage: String = "AI Not Started".localized
    @Published var analysisResult: AnalysisResult? = nil
    @Published var logEntries: [BoardViewModel.LogEntry] = []
    @Published var showAllLogs: Bool = false {
        didSet {
            Task {
                await analysisEngine?.setLoggingEnabled(enabled: showAllLogs)
            }
            if !showAllLogs {
                self.logEntries.removeAll { $0.isCommunication }
            }
        }
    }
    @Published var winRateHistory: [Int: Double] = [:]
    @Published var scoreLeadHistory: [Int: Double] = [:]
    @Published var blunders: [Int: BoardViewModel.BlunderType] = [:]
    @Published var isFullGameScanning: Bool = false
    var blunderThreshold: Double = 15.0

    private var analysisEngine: AnalysisEngine? = nil
    private var analysisTask: Task<Void, Never>? = nil
    private var resultTask: Task<Void, Never>? = nil
    private var logTask: Task<Void, Never>? = nil
    private var fullGameScanTask: Task<Void, Never>? = nil

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
                self.startLogPolling()
                self.startResultPolling()
            } catch {
                self.isAnalyzing = false
                self.isEngineStarted = false
                self.engineMessage = "AI Error: \(error)".localized
                self.addLog("AI Error: \(error)", isError: true)
            }
        }
    }

    func stop() {
        isAnalyzing = false
        isEngineStarted = false
        isEngineReady = false
        analysisResult = nil
        winRateHistory = [:]
        scoreLeadHistory = [:]
        blunders = [:]
        analysisTask?.cancel()
        analysisTask = nil
        fullGameScanTask?.cancel()
        fullGameScanTask = nil
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
        guard isAnalyzing, let engine = analysisEngine else {
            analysisResult = nil
            return
        }

        self.currentNodeId = currentNodeId
        self.currentTurnColorIsWhite = (nextPlayer == "W")
        self.currentTurnNumber = turnNumber
        self.blunderThreshold = config.display.blunderThreshold

        analysisTask?.cancel()

        let analysisSettings = config.analysis
        let displaySettings = config.display

        analysisTask = Task {
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

                try await engine.analyze(queryJson: jsonString)
            } catch is CancellationError {
            } catch {
                print("Analysis error: \(error)")
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

        fullGameScanTask?.cancel()
        isFullGameScanning = true

        fullGameScanTask = Task {
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
        fullGameScanTask?.cancel()
        fullGameScanTask = nil
        isFullGameScanning = false
    }

    func resetSession() {
        self.analysisSessionId += 1
        self.winRateHistory = [:]
        self.scoreLeadHistory = [:]
        self.blunders = [:]
        self.analysisResult = nil
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
        let entry = BoardViewModel.LogEntry(message: displayMessage, isError: finalIsError, isCommunication: isComm)

        self.logEntries.append(entry)
        if self.logEntries.count > 2000 {
            self.logEntries.removeFirst(500)
        }

        if trimmed.contains("Started, ready to begin handling requests") {
            if !self.isEngineReady {
                self.isEngineReady = true
                self.engineMessage = "AI Started".localized
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

        let parts = result.id.split(separator: "-")
        if result.id.hasPrefix("qidao-") || result.id.hasPrefix("fullscan-") {
            if parts.count >= 2, let resultSessionId = Int(parts[1]) {
                if resultSessionId != self.analysisSessionId { return }
            }
        }

        if result.id.hasPrefix("qidao-") {
            if result.id.hasSuffix("-\(currentNodeId)") {
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
            if !result.isDuringSearch {
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
