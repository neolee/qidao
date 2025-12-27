import Foundation
import Combine
import qidao_coreFFI

struct Variation: Identifiable {
    let id: Int
    let moveText: String
    let x: Int?
    let y: Int?

    var label: String {
        if id < 26 {
            return String(UnicodeScalar(UInt8(ascii: "A") + UInt8(id)))
        } else {
            return "\(id + 1)"
        }
    }
}

struct TreeVisualNode: Identifiable {
    let id: String
    let x: CGFloat
    let y: CGFloat
    let color: StoneColor?
}

struct TreeVisualEdge: Identifiable {
    let id: String
    let from: CGPoint
    let to: CGPoint
}

enum MoveNumberDisplay: Int, CaseIterable, Identifiable {
    case all = 0
    case last10 = 10
    case last5 = 5
    case last1 = 1
    case none = -1

    var id: Int { self.rawValue }

    var label: String {
        switch self {
        case .all: return "All".localized
        case .last10: return "Last 10".localized
        case .last5: return "Last 5".localized
        case .last1: return "Last 1".localized
        case .none: return "None".localized
        }
    }
}

enum MarkerType {
    case last1 // -1
    case last2 // -2
    case last3 // -3
}

@MainActor
class BoardViewModel: ObservableObject {
    @Published var message: String = "Ready".localized
    @Published var gameInfo: String = ""
    @Published var board: Board = Board(size: 19)
    @Published var nextColor: StoneColor = .black
    @Published var theme: BoardTheme = .defaultWood
    @Published var moveNumberDisplay: MoveNumberDisplay = .all {
        didSet { UserDefaults.standard.set(moveNumberDisplay.rawValue, forKey: "moveNumberDisplay") }
    }
    @Published var showCoordinates: Bool = true {
        didSet { UserDefaults.standard.set(showCoordinates, forKey: "showCoordinates") }
    }
    @Published var playSound: Bool = true {
        didSet { UserDefaults.standard.set(playSound, forKey: "playSound") }
    }
    @Published var lastMove: (x: Int, y: Int)? = nil
    @Published var moveCount: Int = 0
    @Published var maxMoveCount: Int = 0
    @Published var variations: [Variation] = []
    @Published var treeNodes: [TreeVisualNode] = []
    @Published var treeEdges: [TreeVisualEdge] = []
    @Published var currentNodeId: String = ""

    var nextSgfMove: (x: Int, y: Int)? {
        let children = game.getCurrentNode().getChildren()
        if let first = children.first {
            let props = first.getProperties()
            if let moveProp = props.first(where: { $0.identifier == "B" || $0.identifier == "W" }),
               let coords = moveProp.values.first, coords.count == 2 {
                let x = Int(coords.first!.asciiValue! - UInt8(ascii: "a"))
                let y = Int(coords.last!.asciiValue! - UInt8(ascii: "a"))
                return (x, y)
            }
        }
        return nil
    }

    func shouldShowMoveNumber(_ moveNum: Int?) -> Bool {
        guard let moveNum = moveNum else { return false }
        switch moveNumberDisplay {
        case .all: return true
        case .none: return false
        default:
            return moveNum > (moveCount - moveNumberDisplay.rawValue)
        }
    }

    func getMarkerType(x: Int, y: Int, moveNumber: Int?) -> MarkerType? {
        guard let moveNum = moveNumber else { return nil }
        // Only show markers if move numbers are NOT shown for this stone
        if shouldShowMoveNumber(moveNum) { return nil }

        if moveNum == moveCount { return .last1 }
        if moveNum == moveCount - 1 { return .last2 }
        if moveNum == moveCount - 2 { return .last3 }
        return nil
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let message: String
        let isError: Bool
        let isCommunication: Bool
    }

    // AI Analysis
    @Published var isAnalyzing: Bool = false
    @Published var engineMessage: String = "AI Not Started".localized
    @Published var analysisResult: AnalysisResult? = nil
    @Published var logEntries: [LogEntry] = []
    @Published var showAllLogs: Bool = false
    @Published var winRateHistory: [Double] = []
    @Published var scoreLeadHistory: [Double] = []
    @Published var hoveredVariation: [String]? = nil
    @Published var config = ConfigManager.shared.config

    private var analysisEngine: AnalysisEngine? = nil
    private var analysisTask: Task<Void, Never>? = nil
    private var logTask: Task<Void, Never>? = nil
    private var isEngineReady: Bool = false

    var treeWidth: CGFloat {
        let maxX = treeNodes.map { $0.x }.max() ?? 0
        return maxX
    }

    var treeHeight: CGFloat {
        let maxY = treeNodes.map { $0.y }.max() ?? 0
        return maxY
    }

    @Published var metadata: GameMetadata = GameMetadata(
        blackName: "", blackRank: "",
        whiteName: "", whiteRank: "",
        komi: 7.5, result: "",
        date: "", event: "",
        gameName: "", place: "",
        size: 19
    )

    private var nodeMap: [String: SgfNode] = [:]

    var formattedResult: String {
        let res = metadata.result.trimmingCharacters(in: .whitespacesAndNewlines)
        if res.isEmpty { return "" }

        let upperRes = res.uppercased()
        if upperRes.hasPrefix("B+") {
            let score = res.dropFirst(2)
            if score.uppercased() == "R" || score.uppercased() == "RESIGN" {
                return "Black wins by resignation".localized
            }
            if score.uppercased() == "T" || score.uppercased() == "TIME" {
                return "Black wins by time".localized
            }
            return "\("Black wins by".localized) \(score) \("points".localized)"
        } else if upperRes.hasPrefix("W+") {
            let score = res.dropFirst(2)
            if score.uppercased() == "R" || score.uppercased() == "RESIGN" {
                return "White wins by resignation".localized
            }
            if score.uppercased() == "T" || score.uppercased() == "TIME" {
                return "White wins by time".localized
            }
            return "\("White wins by".localized) \(score) \("points".localized)"
        } else if upperRes == "DRAW" {
            return "Draw".localized
        } else if upperRes == "VOID" {
            return "Void".localized
        }
        return res
    }

    private var cancellables = Set<AnyCancellable>()
    var langManager = LanguageManager.shared

    // Core Game Controller
    private var game: Game

    // Track move history for numbering
    @Published var moveNumbers: [String: Int] = [:]

    init() {
        // Initialize Game Controller
        self.game = Game(size: 19)

        // Load persisted settings
        if let rawValue = UserDefaults.standard.object(forKey: "moveNumberDisplay") as? Int,
           let display = MoveNumberDisplay(rawValue: rawValue) {
            self.moveNumberDisplay = display
        } else {
            // Migration from old showMoveNumbers
            let oldShow = UserDefaults.standard.object(forKey: "showMoveNumbers") as? Bool ?? true
            self.moveNumberDisplay = oldShow ? .all : .none
        }
        self.showCoordinates = UserDefaults.standard.object(forKey: "showCoordinates") as? Bool ?? true
        self.playSound = UserDefaults.standard.object(forKey: "playSound") as? Bool ?? true

        let themeId = UserDefaults.standard.string(forKey: "selectedThemeId") ?? "wood"
        self.theme = (themeId == "bw") ? .bwPrint : .defaultWood

        // Observe language changes to refresh message
        LanguageManager.shared.$selectedLanguage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMessage()
            }
            .store(in: &cancellables)

        // Initial sync to ensure correct state
        syncStateWithGame(rebuildTree: true)
    }

    private func refreshMessage() {
        if moveCount == 0 {
            message = "Ready".localized
        } else if let last = lastMove {
            // The last move was made by the color opposite to nextColor
            let lastColor = (nextColor == .black) ? "White" : "Black"
            let colorStr = lastColor.localized
            message = "\("Move".localized) \(moveCount): \(colorStr) at (\(last.x), \(last.y))"
        } else {
            message = "Board Reset".localized
        }
    }

    func placeStone(x: Int, y: Int) {
        do {
            let color = nextColor
            let currentBoard = game.getBoard()
            let oldStoneCount = countStones(on: currentBoard)

            // Use Game controller to place stone
            try game.placeStone(x: UInt32(x), y: UInt32(y), color: color)

            let newBoard = game.getBoard()
            let newStoneCount = countStones(on: newBoard)

            // Play sound based on captures
            let captures = oldStoneCount + 1 - newStoneCount

            if captures == 0 {
                SoundManager.shared.play(name: "stone")
            } else if captures == 1 {
                SoundManager.shared.play(name: "dead-stone")
            } else {
                SoundManager.shared.play(name: "dead-stones")
            }

            syncStateWithGame(rebuildTree: true)
        } catch {
            self.message = "\("Invalid Move".localized): \(error)"
        }
    }

    func goBack(playSound: Bool = true) {
        if game.goBack() {
            if playSound {
                // When going back, for consistency with most Go apps, we play a stone sound.
                SoundManager.shared.play(name: "stone")
            }

            syncStateWithGame()
        }
    }

    func goForward(index: Int = 0) {
        let currentBoard = game.getBoard()
        let oldStoneCount = countStones(on: currentBoard)
        if game.goForward(index: UInt32(index)) {
            let newBoard = game.getBoard()
            let newStoneCount = countStones(on: newBoard)

            // Calculate captures: (old + 1) - new
            let captures = oldStoneCount + 1 - newStoneCount

            if captures == 0 {
                SoundManager.shared.play(name: "stone")
            } else if captures == 1 {
                SoundManager.shared.play(name: "dead-stone")
            } else {
                SoundManager.shared.play(name: "dead-stones")
            }

            syncStateWithGame()
        }
    }

    func nextVariation() {
        let count = Int(game.getVariationCount())
        if count > 1 {
            let currentIndex = Int(game.getCurrentVariationIndex())
            let nextIndex = (currentIndex + 1) % count
            // Go back silently and then forward to the next variation
            if game.goBack() {
                goForward(index: nextIndex)
            }
        }
    }

    func previousVariation() {
        let count = Int(game.getVariationCount())
        if count > 1 {
            let currentIndex = Int(game.getCurrentVariationIndex())
            let prevIndex = (currentIndex - 1 + count) % count
            // Go back silently and then forward to the previous variation
            if game.goBack() {
                goForward(index: prevIndex)
            }
        }
    }

    func selectVariation(_ index: Int) {
        goForward(index: index)
    }

    func goToStart() {
        while game.canGoBack() {
            _ = game.goBack()
        }
        syncStateWithGame()
    }

    func goToEnd() {
        while game.canGoForward() {
            _ = game.goForward(index: 0)
        }
        syncStateWithGame()
    }

    func jumpToMove(_ target: Int) {
        game.jumpToMoveNumber(target: UInt32(target))
        syncStateWithGame()
    }

    func jumpToNode(id: String) {
        if let node = nodeMap[id] {
            game.jumpToNode(target: node)
            syncStateWithGame()
        }
    }

    // MARK: - AI Analysis

    func toggleAnalysis() {
        if isAnalyzing {
            stopAnalysis()
        } else {
            startAnalysis()
        }
    }

    func startAnalysis() {
        guard analysisEngine == nil else { return }

        isAnalyzing = true
        isEngineReady = false
        engineMessage = "Starting AI...".localized

        let profile = ConfigManager.shared.currentProfile
        let executable = profile.path
        var args = profile.extraArgs.split(separator: " ").map(String.init)

        // If no args provided, default to analysis mode
        if args.isEmpty {
            args = ["analysis"]
        }

        if !profile.config.isEmpty {
            args.append("-config")
            args.append(profile.config)
        }
        if !profile.model.isEmpty {
            args.append("-model")
            args.append(profile.model)
        }

        // Validation: KataGo analysis mode requires a config file
        if args.contains("analysis") && profile.config.isEmpty {
            self.isAnalyzing = false
            self.message = "Error: Config file is required for analysis mode".localized
            self.addLog("[ERROR] Config file is required. Please set it in Engine Settings.", isError: true)
            return
        }

        Task {
            do {
                let engine = AnalysisEngine()
                try await engine.start(executable: executable, args: args)
                self.analysisEngine = engine
                // engineMessage will be updated via logs
                self.startLogPolling()
                updateAnalysis()
            } catch {
                self.isAnalyzing = false
                self.engineMessage = "AI Error: \(error)".localized
                self.addLog("AI Error: \(error)", isError: true)
            }
        }
    }

    private func addLog(_ message: String, isError: Bool = false) {
        var displayMessage = message
        let isStderrPrefixed = message.hasPrefix("[STDERR]")
        if isStderrPrefixed {
            // Remove "[STDERR] " prefix if present, otherwise just "[STDERR]"
            if message.hasPrefix("[STDERR] ") {
                displayMessage = String(message.dropFirst(9))
            } else {
                displayMessage = String(message.dropFirst(8))
            }
        }

        let trimmed = displayMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        
        // Communication logs start with >>> or <<<
        let isComm = trimmed.hasPrefix(">>>") || trimmed.hasPrefix("<<<")
        
        // Improved error detection for engine logs
        let lowerTrimmed = trimmed.lowercased()
        let containsErrorMarker = lowerTrimmed.contains("[error]") || 
                                 lowerTrimmed.contains("fatal error") || 
                                 lowerTrimmed.hasPrefix("error:") ||
                                 lowerTrimmed.contains(" error: ")
        
        // If it's from stderr, we only treat it as an error if it has a strong error marker.
        let finalIsError = isError || containsErrorMarker

        let entry = LogEntry(message: displayMessage, isError: finalIsError, isCommunication: isComm)

        DispatchQueue.main.async {
            self.logEntries.append(entry)
            if self.logEntries.count > 500 {
                self.logEntries.removeFirst(100)
            }

            // Update engine status message
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
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
        }
    }

    func stopAnalysis() {
        isAnalyzing = false
        isEngineReady = false
        analysisResult = nil
        analysisTask?.cancel()
        analysisTask = nil
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

    func updateAnalysis() {
        guard isAnalyzing, let engine = analysisEngine else {
            analysisResult = nil
            return
        }

        analysisTask?.cancel()
        // Don't clear analysisResult here to avoid UI flickering.
        // The UI will keep showing the previous result until new data arrives.

        let initialStones = game.getCurrentBoardStones()
        let nextPlayer = nextColor == .black ? "B" : "W"
        let currentNodeId = game.getCurrentNode().getId()
        let analysisSettings = config.analysis
        let displaySettings = config.display
        let metadataSnapshot = metadata
        let analyzingWhiteToMove = nextColor == .white

        analysisTask = Task {
            do {
                // Debounce: wait for 0.5 seconds before starting analysis (reduced from 1s)
                try await Task.sleep(nanoseconds: 500_000_000)

                var query: [String: Any] = [
                    "id": "qidao-\(currentNodeId)",
                    "moves": [] as [Any],
                    "initialStones": initialStones,
                    "initialPlayer": nextPlayer,
                    "rules": "chinese",
                    "komi": metadataSnapshot.komi,
                    "boardXSize": metadataSnapshot.size,
                    "boardYSize": metadataSnapshot.size,
                    "analyzeTurns": [0],
                    "includeOwnership": displaySettings.showOwnership,
                    "includePolicy": analysisSettings.includePolicy
                ]

                if let reportInterval = analysisSettings.reportDuringSearchEvery, reportInterval >= 0.001 {
                    query["reportDuringSearchEvery"] = reportInterval
                }

                if let maxVisits = analysisSettings.maxVisits {
                    query["maxVisits"] = maxVisits
                }

                var overrideSettings: [String: Any] = [:]
                if let maxTime = analysisSettings.maxTime {
                    overrideSettings["maxTime"] = maxTime
                }

                for (key, value) in analysisSettings.advancedParams {
                    // Try to parse as Bool, then Double, then fallback to String
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

                // Continuous update loop
                while !Task.isCancelled {
                    do {
                        let result = try await engine.getNextResult()
                        if !Task.isCancelled && result.id == "qidao-\(currentNodeId)" {
                            // Normalize to Black's perspective for history and sidebar displays
                            let normalizedWinRate = WinRateConverter.convertWinRate(
                                result.rootInfo.winrate,
                                reportedAs: .black,
                                target: .black,
                                isWhiteTurn: analyzingWhiteToMove
                            )
                            let normalizedScoreLead = WinRateConverter.convertScoreLead(
                                result.rootInfo.scoreLead,
                                reportedAs: .black,
                                target: .black,
                                isWhiteTurn: analyzingWhiteToMove
                            )

                            let normalizedResult = AnalysisResult(
                                id: result.id,
                                turnNumber: result.turnNumber,
                                rootInfo: AnalysisRootInfo(
                                    winrate: normalizedWinRate,
                                    scoreLead: normalizedScoreLead,
                                    visits: result.rootInfo.visits
                                ),
                                moveInfos: result.moveInfos,
                                ownership: result.ownership
                            )

                            self.analysisResult = normalizedResult

                            // Update history for the current turn
                            let turn = self.moveCount
                            if self.winRateHistory.count > turn {
                                self.winRateHistory[turn] = normalizedWinRate
                                self.scoreLeadHistory[turn] = normalizedScoreLead
                            } else {
                                while self.winRateHistory.count < turn {
                                    self.winRateHistory.append(0.5)
                                    self.scoreLeadHistory.append(0.0)
                                }
                                self.winRateHistory.append(normalizedWinRate)
                                self.scoreLeadHistory.append(normalizedScoreLead)
                            }

                            // If we reached max visits, we can stop polling for this turn
                            if let maxVisits = analysisSettings.maxVisits, result.rootInfo.visits >= UInt32(maxVisits) {
                                break
                            }
                        }
                    } catch {
                        let errorMsg = "\(error)"
                        if !errorMsg.contains("Timeout") {
                            self.addLog("[ERROR] \(errorMsg)", isError: true)
                        }
                        
                        // If no result yet or timeout, wait a bit
                        if Task.isCancelled { break }
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    }
                }
            } catch is CancellationError {
                // Task was cancelled, ignore
            } catch {
                print("Analysis error: \(error)")
            }
        }
    }

    private func rebuildTree() {
        nodeMap = [:]
        var nodes: [TreeVisualNode] = []
        var edges: [TreeVisualEdge] = []

        let root = game.getRootNode()

        var nextXAtDepth: [Int: Int] = [:]

        func traverse(node: SgfNode, depth: Int, xOffset: Int, parentPos: CGPoint?) {
            let id = node.getId()
            nodeMap[id] = node

            let x = CGFloat(xOffset)
            let y = CGFloat(depth)
            let currentPos = CGPoint(x: x, y: y)

            let props = node.getProperties()
            var color: StoneColor? = nil
            if props.contains(where: { $0.identifier == "B" }) {
                color = .black
            } else if props.contains(where: { $0.identifier == "W" }) {
                color = .white
            }

            nodes.append(TreeVisualNode(id: id, x: x, y: y, color: color))

            if let parent = parentPos {
                edges.append(TreeVisualEdge(id: "\(id)-edge", from: parent, to: currentPos))
            }

            let children = node.getChildren()
            let currentX = xOffset
            for (index, child) in children.enumerated() {
                let childX = (index == 0) ? currentX : (nextXAtDepth[depth + 1] ?? currentX + 1)
                nextXAtDepth[depth + 1] = max(nextXAtDepth[depth + 1] ?? 0, childX + 1)
                traverse(node: child, depth: depth + 1, xOffset: childX, parentPos: currentPos)
            }
        }

        traverse(node: root, depth: 0, xOffset: 0, parentPos: nil)

        self.treeNodes = nodes
        self.treeEdges = edges
    }

    private func syncStateWithGame(rebuildTree: Bool = false) {
        // Ensure updates happen on main thread and outside immediate view update cycle
        DispatchQueue.main.async {
            self.analysisResult = nil // Clear AI overlay immediately on move
            self.board = self.game.getBoard()
            self.nextColor = self.game.getNextColor()
            self.moveCount = Int(self.game.getMoveCount())
            self.maxMoveCount = Int(self.game.getMaxMoveCount())
            self.metadata = self.game.getMetadata()
            self.currentNodeId = self.game.getCurrentNode().getId()

            // Update lastMove
            if let last = self.game.getLastMove(), let coords = last.values.first, coords.count == 2 {
                let x = Int(coords.first!.asciiValue! - UInt8(ascii: "a"))
                let y = Int(coords.last!.asciiValue! - UInt8(ascii: "a"))
                self.lastMove = (x, y)
            } else {
                self.lastMove = nil
            }

            // Rebuild moveNumbers map
            self.moveNumbers = [:]
            let pathMoves = self.game.getCurrentPathMoves()
            for (index, moveProp) in pathMoves.enumerated() {
                if let coords = moveProp.values.first, coords.count == 2 {
                    let x = Int(coords.first!.asciiValue! - UInt8(ascii: "a"))
                    let y = Int(coords.last!.asciiValue! - UInt8(ascii: "a"))
                    self.moveNumbers["\(x),\(y)"] = index + 1
                }
            }

            // Update variations: Show A, B, C... only if there are multiple branches.
            // If there's only one branch, don't show any variation marker.
            let children = self.game.getCurrentNode().getChildren()
            let variationChildren = children.count > 1 ? children : []
            self.variations = variationChildren.enumerated().map { (index, node) in
                let props = node.getProperties()
                let moveProp = props.first { $0.identifier == "B" || $0.identifier == "W" }
                var vx: Int? = nil
                var vy: Int? = nil
                let moveText: String
                if let prop = moveProp, let coords = prop.values.first, coords.count == 2 {
                    vx = Int(coords.first!.asciiValue! - UInt8(ascii: "a"))
                    vy = Int(coords.last!.asciiValue! - UInt8(ascii: "a"))
                    moveText = "\(prop.identifier) (\(vx!), \(vy!))"
                } else {
                    moveText = "Node \(index + 1)"
                }
                return Variation(id: index, moveText: moveText, x: vx, y: vy)
            }

            if rebuildTree {
                self.rebuildTree()
            }
            self.refreshMessage()
            self.updateAnalysis()
        }
    }

    private func countStones(on board: Board) -> Int {
        var count = 0
        let size = board.getSize()
        for y in 0..<size {
            for x in 0..<size {
                if board.getStone(x: x, y: y) != nil {
                    count += 1
                }
            }
        }
        return count
    }

    func getDisplayMoveNumber(x: Int, y: Int) -> Int? {
        guard let num = moveNumbers["\(x),\(y)"] else { return nil }
        switch moveNumberDisplay {
        case .all: return num
        case .none: return nil
        default:
            if num > moveCount - moveNumberDisplay.rawValue {
                return num
            } else {
                return nil
            }
        }
    }

    func resetBoard() {
        self.game = Game(size: 19)
        syncStateWithGame(rebuildTree: true)
        self.message = "Board Reset".localized
    }

    func toggleTheme() {
        theme = (theme.id == "wood") ? .bwPrint : .defaultWood
        UserDefaults.standard.set(theme.id, forKey: "selectedThemeId")
    }

    func updateMetadata(_ newMetadata: GameMetadata) {
        game.setMetadata(metadata: newMetadata)
        syncStateWithGame(rebuildTree: true)
    }

    func loadSgf(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            var content: String?

            // Try UTF-8 first
            content = String(data: data, encoding: .utf8)

            // If failed, try GB18030 (common for Chinese SGFs)
            if content == nil {
                let gbkEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                content = String(data: data, encoding: String.Encoding(rawValue: gbkEncoding))
            }

            // Fallback to ASCII if all else fails
            if content == nil {
                content = String(data: data, encoding: .ascii)
            }

            guard let sgfContent = content else {
                self.message = "\("Load Failed".localized): \("Failed to decode SGF file".localized)"
                return
            }

            self.game = try Game.fromSgf(sgfContent: sgfContent)
            syncStateWithGame(rebuildTree: true)
            self.message = "\("Loaded".localized): \(url.lastPathComponent)"
        } catch {
            self.message = "\("Load Failed".localized): \(error.localizedDescription)"
        }
    }

    func saveSgf(url: URL) {
        do {
            let content = game.toSgf()
            try content.write(to: url, atomically: true, encoding: .utf8)
            self.message = "\("Saved".localized): \(url.lastPathComponent)"
        } catch {
            self.message = "\("Save Failed".localized): \(error.localizedDescription)"
        }
    }

    func decodeKataGoMove(_ move: String) -> (x: Int, y: Int)? {
        let move = move.uppercased()
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
        let y = Int(metadata.size) - row

        return (x, y)
    }
}
