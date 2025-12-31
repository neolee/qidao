import Foundation
import Combine
import qidao_coreFFI

@MainActor
class BoardViewModel: ObservableObject {
    @Published private(set) var gameState = GameState()

    // Computed properties for backward compatibility with views and engine
    var board: Board { gameState.board }
    var boardSize: Int {
        get { gameState.boardSize }
        set { changeBoardSize(newValue) }
    }
    var isSizeLocked: Bool {
        get { gameState.isSizeLocked }
        set { gameManager.internalState.isSizeLocked = newValue }
    }
    var nextColor: StoneColor { gameState.nextColor }
    var lastMove: (x: Int, y: Int)? { gameState.lastMove }
    var moveCount: Int { gameState.moveCount }
    var maxMoveCount: Int { gameState.maxMoveCount }
    var variations: [Variation] { gameState.variations }
    var treeNodes: [TreeVisualNode] { gameState.treeNodes }
    var treeEdges: [TreeVisualEdge] { gameState.treeEdges }
    var currentNodeId: String { gameState.currentNodeId }
    var nodeComment: String { gameState.nodeComment }
    var moveNumbers: [String: Int] { gameState.moveNumbers }
    var metadata: GameMetadata { gameState.metadata }

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

    @Published var appMode: AppMode = .analysis {
        didSet {
            if appMode == .play {
                aiManager.clearAnalysisResult()
                checkAIMove()
                startClock()
            } else if appMode == .analysis {
                aiPlayTask?.cancel()
                aiPlayTask = nil
                aiManager.cancelPlay()
                updateAnalysis()
                stopClock()
            } else {
                aiPlayTask?.cancel()
                aiPlayTask = nil
                aiManager.cancelPlay()
                aiManager.clearAnalysisResult()
                stopClock()
            }
        }
    }

    @Published var activeEditTool: EditTool = .stoneAuto
    @Published var editLabelText: String = "A"

    // MARK: - Play Mode Clock
    @Published var playTimeSettings = PlayTimeSettings()
    @Published var clockState: PlayClockState? = nil
    @Published var showTimeoutDialog = false
    private var clockTimer: Timer? = nil

    @Published var aiRole: AIRole = .manual {
        didSet {
            if appMode == .play {
                checkAIMove()
            }
        }
    }

    var nextSgfMove: (x: Int, y: Int)? {
        let children = gameManager.getGame().getCurrentNode().getChildren()
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

    func getDisplayMoveNumber(x: Int, y: Int) -> Int? {
        if let moveNum = moveNumbers["\(x),\(y)"], shouldShowMoveNumber(moveNum) {
            return moveNum
        }
        return nil
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

    func handleBoardClick(x: Int, y: Int) {
        switch appMode {
        case .analysis:
            placeStone(x: x, y: y)
        case .edit:
            handleEditClick(x: x, y: y)
        case .play:
            // TODO: Implement play mode logic
            placeStone(x: x, y: y)
        }
    }

    private func handleEditClick(x: Int, y: Int) {
        let game = gameManager.getGame()
        let currentStone = board.getStone(x: UInt32(x), y: UInt32(y))

        switch activeEditTool {
        case .stoneBlack:
            if currentStone == .black {
                game.removeStone(x: UInt32(x), y: UInt32(y))
            } else {
                game.addStone(x: UInt32(x), y: UInt32(y), color: .black)
            }
        case .stoneWhite:
            if currentStone == .white {
                game.removeStone(x: UInt32(x), y: UInt32(y))
            } else {
                game.addStone(x: UInt32(x), y: UInt32(y), color: .white)
            }
        case .stoneAuto:
            // Toggle: Empty -> Black -> White -> Empty
            if currentStone == nil {
                game.addStone(x: UInt32(x), y: UInt32(y), color: .black)
            } else if currentStone == .black {
                game.addStone(x: UInt32(x), y: UInt32(y), color: .white)
            } else {
                game.removeStone(x: UInt32(x), y: UInt32(y))
            }
        case .markTriangle, .markCircle, .markSquare, .markCross:
            let markType = activeEditTool.markType!
            if gameState.marks.contains(where: { $0.x == x && $0.y == y && $0.type == markType }) {
                game.clearMarks(x: UInt32(x), y: UInt32(y))
            } else {
                game.addMark(x: UInt32(x), y: UInt32(y), markType: markType)
            }
        case .markLabel:
            if gameState.marks.contains(where: { $0.x == x && $0.y == y && $0.type == "LB" && $0.label == editLabelText }) {
                game.clearMarks(x: UInt32(x), y: UInt32(y))
            } else {
                game.addLabel(x: UInt32(x), y: UInt32(y), label: editLabelText)
                // Auto increment label if it's a number
                if let num = Int(editLabelText) {
                    editLabelText = "\(num + 1)"
                } else if editLabelText.count == 1, let char = editLabelText.first, char.isLetter {
                    if let scalar = char.unicodeScalars.first {
                        if let next = UnicodeScalar(scalar.value + 1), Character(next).isLetter {
                            editLabelText = String(next)
                        }
                    }
                }
            }
        case .clear:
            game.removeStone(x: UInt32(x), y: UInt32(y))
            game.clearMarks(x: UInt32(x), y: UInt32(y))
        }

        // Refresh game state
        gameManager.syncState()
    }

    func pass() {
        try? gameManager.getGame().pass(color: nextColor)
        gameManager.syncState()
        updateClockOnMove()
        if isAnalyzing {
            updateAnalysis()
        }
    }

    func resign() {
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

    func deleteCurrentBranch() {
        if gameManager.deleteCurrentBranch() {
            SoundManager.shared.play(name: "stone")
        }
    }

    func setNextPlayer(_ color: StoneColor) {
        gameManager.getGame().setNextPlayer(color: color)
        gameManager.syncState()
    }

    // AI Analysis
    @Published var isAnalyzing: Bool = false
    @Published var aiStatus: AIStatus = .idle
    @Published var engineMessage: String = "AI Not Started".localized
    @Published var analysisResult: AnalysisResult? = nil
    @Published var logEntries: [EngineLog] = []
    @Published var showAllLogs: Bool = false {
        didSet {
            aiManager.showAllLogs = showAllLogs
        }
    }
    @Published var winRateHistory: [Int: Double] = [:]
    @Published var scoreLeadHistory: [Int: Double] = [:]
    @Published var blunders: [Int: BlunderType] = [:]
    @Published var hoveredMoveStr: String? = nil
    @Published var config = ConfigManager.shared.config {
        didSet {
            if !config.display.showWinRateGraph {
                stopFullGameAnalysis()
            } else if isAnalyzing && !oldValue.display.showWinRateGraph {
                startFullGameAnalysis()
            }
        }
    }
    @Published var isFullGameScanning: Bool = false

    var gameManager: GameManager
    var aiManager: AIManager
    var aiPlayTask: Task<Void, Never>? = nil
    var sgfManager = SgfManager()
    private var cancellables = Set<AnyCancellable>()

    var treeWidth: CGFloat {
        let maxX = treeNodes.map { $0.x }.max() ?? 0
        return maxX
    }

    var treeHeight: CGFloat {
        let maxY = treeNodes.map { $0.y }.max() ?? 0
        return maxY
    }

    var langManager = LanguageManager.shared

    init() {
        // Load persisted settings
        let savedSize = UserDefaults.standard.integer(forKey: "boardSize")
        let initialSize = savedSize > 0 ? savedSize : 19

        self.gameManager = GameManager(initialSize: initialSize)
        self.aiManager = AIManager()

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

        setupBindings()
    }

    private func setupBindings() {
        gameManager.$gameState
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.gameState = $0
                self?.updateAnalysis()
                if self?.appMode == .play {
                    self?.checkAIMove()
                }
            }
            .store(in: &cancellables)

        aiManager.$isAnalyzing.assign(to: &$isAnalyzing)
        aiManager.$aiStatus.assign(to: &$aiStatus)

        // Trigger AI move check when engine becomes ready or analysis starts
        Publishers.CombineLatest(aiManager.$isAnalyzing, aiManager.$isEngineReady)
            .receive(on: RunLoop.main)
            .sink { [weak self] analyzing, ready in
                if analyzing && ready && self?.appMode == .play {
                    self?.checkAIMove()
                }
            }
            .store(in: &cancellables)

        aiManager.$isEngineReady
            .receive(on: RunLoop.main)
            .sink { [weak self] ready in
                if ready {
                    self?.updateAnalysis()
                    self?.startFullGameAnalysis()
                }
            }
            .store(in: &cancellables)
        aiManager.$engineMessage.assign(to: &$engineMessage)
        aiManager.$analysisResult.assign(to: &$analysisResult)
        aiManager.$logEntries.assign(to: &$logEntries)
        aiManager.$winRateHistory.assign(to: &$winRateHistory)
        aiManager.$scoreLeadHistory.assign(to: &$scoreLeadHistory)
        aiManager.$blunders.assign(to: &$blunders)
        aiManager.$isFullGameScanning.assign(to: &$isFullGameScanning)
    }

    func placeStone(x: Int, y: Int) {
        do {
            let captures = try gameManager.placeStone(x: x, y: y, color: nextColor)
            updateClockOnMove()
            if captures == 0 {
                SoundManager.shared.play(name: "stone")
            } else if captures == 1 {
                SoundManager.shared.play(name: "dead-stone")
            } else {
                SoundManager.shared.play(name: "dead-stones")
            }
        } catch {
            SoundManager.shared.playAlert()
        }
    }

    private func checkAIMove() {
        guard appMode == .play, isAnalyzing, aiStatus == .ready else { return }

        let isAITurn: Bool
        switch aiRole {
        case .manual: isAITurn = false
        case .black: isAITurn = (nextColor == .black)
        case .white: isAITurn = (nextColor == .white)
        case .both: isAITurn = true
        }

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
                    self.placeStone(x: move.x, y: move.y)
                } else {
                    // If AI returns nil, it could be a PASS or an error.
                    // For now we assume it's a PASS if the engine is still ready.
                    self.pass()
                }
            }
        }
    }

    func goBack(playSound: Bool = true) {
        if gameManager.goBack() {
            if playSound {
                SoundManager.shared.play(name: "stone")
            }
        }
    }

    func goForward(index: Int = 0) {
        if let captures = gameManager.goForward(index: index) {
            if captures == 0 {
                SoundManager.shared.play(name: "stone")
            } else if captures == 1 {
                SoundManager.shared.play(name: "dead-stone")
            } else {
                SoundManager.shared.play(name: "dead-stones")
            }
        }
    }

    func nextVariation() {
        let game = gameManager.getGame()
        let count = Int(game.getVariationCount())
        if count > 1 {
            let currentIndex = Int(game.getCurrentVariationIndex())
            let nextIndex = (currentIndex + 1) % count
            if game.goBack() {
                goForward(index: nextIndex)
            }
        }
    }

    func previousVariation() {
        let game = gameManager.getGame()
        let count = Int(game.getVariationCount())
        if count > 1 {
            let currentIndex = Int(game.getCurrentVariationIndex())
            let prevIndex = (currentIndex - 1 + count) % count
            if game.goBack() {
                goForward(index: prevIndex)
            }
        }
    }

    func selectVariation(_ index: Int) {
        goForward(index: index)
    }

    func goToStart() {
        gameManager.jumpToMove(0)
    }

    func goToEnd() {
        gameManager.jumpToMove(maxMoveCount)
    }

    func jumpToMove(_ target: Int) {
        gameManager.jumpToMove(target)
    }

    func jumpToNode(id: String) {
        gameManager.jumpToNode(id: id)
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
        let profile = ConfigManager.shared.currentProfile
        let executable = profile.path
        var args = profile.extraArgs.split(separator: " ").map(String.init)

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

        if args.contains("analysis") && profile.config.isEmpty {
            aiManager.addLog("Error: Config file is required for analysis mode".localized, isError: true)
            return
        }

        aiManager.start(executable: executable, args: args, config: config)
    }

    func stopAnalysis() {
        aiManager.stop()
    }

    func updateAnalysis() {
        self.hoveredMoveStr = nil
        guard appMode == .analysis else {
            // In non-analysis mode, we clear the current analysis result to hide overlays
            aiManager.clearAnalysisResult()
            return
        }

        let game = gameManager.getGame()
        aiManager.updateAnalysis(
            currentNodeId: game.getCurrentNode().getId(),
            initialStones: game.getCurrentBoardStones(),
            nextPlayer: nextColor == .black ? "B" : "W",
            turnNumber: moveCount,
            metadata: game.getMetadata(),
            config: config
        )

        // Trigger background full game analysis if enabled
        if isAnalyzing && config.display.showWinRateGraph {
            startFullGameAnalysis()
        }
    }

    func startFullGameAnalysis() {
        guard appMode == .analysis, config.display.showWinRateGraph else { return }
        let game = gameManager.getGame()

        let mainLineMoves = game.getMainLineMoves()
        let initialStones = game.getInitialStones()

        // Determine initial player without jumping
        var initialPlayer = "B"
        if let firstMove = mainLineMoves.first, firstMove.count > 0 {
            initialPlayer = firstMove[0]
        }

        aiManager.startFullGameAnalysis(
            mainLineMoves: mainLineMoves,
            initialStones: initialStones,
            metadata: game.getMetadata(),
            config: config,
            initialPlayer: initialPlayer
        )
    }

    func stopFullGameAnalysis() {
        aiManager.stopFullGameAnalysis()
    }

    func resetBoard() {
        aiManager.resetSession()
        gameManager.reset(size: boardSize)
    }

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

    func changeBoardSize(_ newSize: Int) {
        guard !isSizeLocked else { return }
        UserDefaults.standard.set(newSize, forKey: "boardSize")
        resetBoard()
    }

    func toggleTheme() {
        theme = (theme.id == "wood") ? .bwPrint : .defaultWood
        UserDefaults.standard.set(theme.id, forKey: "selectedThemeId")
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

    // MARK: - Clock Logic

    func startClock() {
        guard appMode == .play, playTimeSettings.isEnabled else { return }
        if clockState == nil {
            clockState = PlayClockState(humanReserveRemaining: playTimeSettings.humanReserveTime)
        }
        clockState?.currentMoveStartTime = Date()
        
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

    private func tickClock() {
        guard let state = clockState, !state.isTimeout, appMode == .play else { return }
        
        let isHumanTurn: Bool
        switch aiRole {
        case .manual: isHumanTurn = true
        case .white: isHumanTurn = (nextColor == .black)
        case .black: isHumanTurn = (nextColor == .white)
        case .both: isHumanTurn = false
        }
        
        if isHumanTurn && aiManager.aiStatus != .thinking {
            if let startTime = state.currentMoveStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                let remainingInMove = playTimeSettings.humanSecondsPerMove - elapsed
                
                // Sound feedback for last 5 seconds
                if remainingInMove <= 5.0 && remainingInMove > 0 {
                    let second = Int(ceil(remainingInMove))
                    if second != state.lastBeepSecond {
                        clockState?.lastBeepSecond = second
                        if playSound {
                            SoundManager.shared.playSystemBeep()
                        }
                    }
                }
                
                if remainingInMove < 0 {
                    let over = -remainingInMove
                    if over >= state.humanReserveRemaining {
                        clockState?.humanReserveRemaining = 0
                        clockState?.isTimeout = true
                        showTimeoutDialog = true
                        stopClock()
                    }
                }
            }
        }
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

    private func updateClockOnMove() {
        guard let state = clockState, playTimeSettings.isEnabled else { return }
        
        // If we have a startTime, it means someone just moved.
        if let startTime = state.currentMoveStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            
            // We only deduct from reserve if it's human's turn
            let wasHumanTurn: Bool
            switch aiRole {
            case .manual: wasHumanTurn = true
            case .white: wasHumanTurn = (nextColor == .white) // nextColor is already toggled
            case .black: wasHumanTurn = (nextColor == .black)
            case .both: wasHumanTurn = false
            }

            if wasHumanTurn && elapsed > playTimeSettings.humanSecondsPerMove {
                let over = elapsed - playTimeSettings.humanSecondsPerMove
                clockState?.humanReserveRemaining = max(0, state.humanReserveRemaining - over)
            }
        }
        
        // Reset move start time for the next player
        clockState?.currentMoveStartTime = Date()
        clockState?.lastBeepSecond = -1
    }
}
