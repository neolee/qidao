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

    // AI Analysis
    @Published var isAnalyzing: Bool = false
    @Published var engineMessage: String = "AI Not Started".localized
    @Published var analysisResult: AnalysisResult? = nil
    @Published var logEntries: [LogEntry] = []
    @Published var showAllLogs: Bool = false {
        didSet {
            aiManager.showAllLogs = showAllLogs
        }
    }
    @Published var winRateHistory: [Int: Double] = [:]
    @Published var scoreLeadHistory: [Int: Double] = [:]
    @Published var blunders: [Int: BlunderType] = [:]
    @Published var hoveredMoveStr: String? = nil
    @Published var config = ConfigManager.shared.config
    @Published var isFullGameScanning: Bool = false

    private var gameManager: GameManager
    private var aiManager: AIManager
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
            }
            .store(in: &cancellables)

        aiManager.$isAnalyzing.assign(to: &$isAnalyzing)
        aiManager.$isEngineStarted
            .receive(on: RunLoop.main)
            .sink { [weak self] started in
                if started {
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
        gameManager.jumpToMove(Int.max)
    }

    func jumpToMove(_ target: Int) {
        gameManager.jumpToMove(target)
    }

    func jumpToNode(id: String) {
        gameManager.jumpToNode(id: id)
    }

    func deleteCurrentBranch() {
        if gameManager.deleteCurrentBranch() {
            SoundManager.shared.play(name: "stone")
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
        let game = gameManager.getGame()
        aiManager.updateAnalysis(
            currentNodeId: game.getCurrentNode().getId(),
            initialStones: game.getCurrentBoardStones(),
            nextPlayer: nextColor == .black ? "B" : "W",
            turnNumber: moveCount,
            metadata: game.getMetadata(),
            config: config
        )
    }

    func startFullGameAnalysis() {
        let game = gameManager.getGame()
        let currentId = game.getCurrentNode().getId()

        // Get initial player by jumping to root temporarily
        game.jumpToMoveNumber(target: 0)
        let initialPlayer = game.getNextColor() == .black ? "B" : "W"

        // Jump back to original position
        gameManager.jumpToNode(id: currentId)

        aiManager.startFullGameAnalysis(
            mainLineMoves: game.getMainLineMoves(),
            initialStones: game.getInitialStones(),
            metadata: game.getMetadata(),
            config: config,
            initialPlayer: initialPlayer
        )
    }

    func resetBoard() {
        aiManager.resetSession()
        gameManager.reset(size: boardSize)
        self.message = "Board Reset".localized
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
