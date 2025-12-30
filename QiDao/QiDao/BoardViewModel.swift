import Foundation
import Combine
import qidao_coreFFI

@MainActor
class BoardViewModel: ObservableObject {
    @Published var message: String = "Ready".localized
    @Published var gameInfo: String = ""

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
            } else if appMode == .analysis {
                aiPlayTask?.cancel()
                aiPlayTask = nil
                aiManager.cancelPlay()
                updateAnalysis()
            } else {
                aiPlayTask?.cancel()
                aiPlayTask = nil
                aiManager.cancelPlay()
                aiManager.clearAnalysisResult()
            }
        }
    }

    @Published var activeEditTool: EditTool = .stoneAuto
    @Published var editLabelText: String = "A"

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
        do {
            try gameManager.getGame().pass(color: nextColor)
            gameManager.syncState()
            if isAnalyzing {
                updateAnalysis()
            }
        } catch {
            message = "Error: \(error.localizedDescription)"
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
            result: "\(winner.first!)+R",
            date: currentMeta.date,
            event: currentMeta.event,
            gameName: currentMeta.gameName,
            place: currentMeta.place,
            size: currentMeta.size
        ))
        gameManager.syncState()
        message = "\(winner) wins by resignation".localized
    }

    func deleteCurrentBranch() {
        if gameManager.deleteCurrentBranch() {
            SoundManager.shared.play(name: "stone")
            message = "Branch deleted".localized
        }
    }

    func setNextPlayer(_ color: StoneColor) {
        gameManager.getGame().setNextPlayer(color: color)
        gameManager.syncState()
    }

    func getMoveText(at moveNumber: Int) -> String {
        let pathMoves = gameManager.getGame().getCurrentPathMoves()
        if moveNumber > 0 && moveNumber <= pathMoves.count {
            let prop = pathMoves[moveNumber - 1]
            let color = prop.identifier == "B" ? "Black".localized : "White".localized
            if let coords = prop.values.first, coords.count == 2 {
                let x = Int(coords.first!.asciiValue! - UInt8(ascii: "a"))
                let y = Int(coords.last!.asciiValue! - UInt8(ascii: "a"))
                // Skip 'I' in Go coordinates
                let colChar = Character(UnicodeScalar(UInt8(ascii: "A") + UInt8(x >= 8 ? x + 1 : x)))
                let rowNum = boardSize - y
                return "\(color) \(colChar)\(rowNum)"
            } else {
                return "\(color) \("Pass".localized)"
            }
        }
        return ""
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

    private var gameManager: GameManager
    private var aiManager: AIManager
    private var aiPlayTask: Task<Void, Never>? = nil
    private var sgfManager = SgfManager()
    private var cancellables = Set<AnyCancellable>()

    var treeWidth: CGFloat {
        let maxX = treeNodes.map { $0.x }.max() ?? 0
        return maxX
    }

    var treeHeight: CGFloat {
        let maxY = treeNodes.map { $0.y }.max() ?? 0
        return maxY
    }

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

        // Observe language changes to refresh message
        LanguageManager.shared.$selectedLanguage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMessage()
            }
            .store(in: &cancellables)
    }

    private func setupBindings() {
        gameManager.$gameState
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.gameState = $0
                self?.refreshMessage()
                self?.updateAnalysis()
                if self?.appMode == .play {
                    self?.checkAIMove()
                }
            }
            .store(in: &cancellables)

        aiManager.$isAnalyzing.assign(to: &$isAnalyzing)
        aiManager.$aiStatus.assign(to: &$aiStatus)
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
            let captures = try gameManager.placeStone(x: x, y: y, color: nextColor)
            if captures == 0 {
                SoundManager.shared.play(name: "stone")
            } else if captures == 1 {
                SoundManager.shared.play(name: "dead-stone")
            } else {
                SoundManager.shared.play(name: "dead-stones")
            }
        } catch {
            self.message = "\("Invalid Move".localized): \(error)"
        }
    }

    private func checkAIMove() {
        guard appMode == .play, isAnalyzing, aiStatus != .thinking else { return }

        let shouldAIPlay: Bool
        switch aiRole {
        case .manual: shouldAIPlay = false
        case .black: shouldAIPlay = (nextColor == .black)
        case .white: shouldAIPlay = (nextColor == .white)
        case .both: shouldAIPlay = true
        }

        if shouldAIPlay {
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
                    config: currentConfig
                )

                if Task.isCancelled { return }

                // Re-check if we are still on the same node after AI finished thinking
                guard self.gameState.currentNodeId == startNodeId else {
                    print("AI Play: Node changed from \(startNodeId) to \(self.gameState.currentNodeId), ignoring move")
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
            self.message = "Error: Config file is required for analysis mode".localized
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
        self.message = "Board Reset".localized
    }

    func startNewGame(size: Int, komi: Double, handicap: Int) {
        aiManager.resetSession()
        gameManager.reset(size: size)
        let game = gameManager.getGame()
        var meta = game.getMetadata()
        meta.komi = komi
        // TODO: Handle handicap stones
        game.setMetadata(metadata: meta)
        gameManager.syncState(rebuildTree: true)
        self.message = "New Game Started".localized
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

            self.message = "\("Loaded".localized): \(url.lastPathComponent)"
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
            self.message = "\("Load Failed".localized): \(error.localizedDescription)"
        }
    }

    func saveSgf(url: URL) {
        do {
            try sgfManager.saveSgf(game: gameManager.getGame(), url: url)
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
