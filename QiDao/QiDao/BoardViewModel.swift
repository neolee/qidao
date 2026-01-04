import Foundation
import Combine
import SwiftUI
import qidao_coreFFI

@MainActor
class BoardViewModel: ObservableObject {
    @Published private(set) var gameState = GameState()

    // Computed properties for backward compatibility with views and engine
    var board: Board { gameManager.internalState.board }
    var boardSize: Int {
        get { gameManager.internalState.boardSize }
        set { changeBoardSize(newValue) }
    }
    var isSizeLocked: Bool {
        get { gameManager.internalState.isSizeLocked }
        set { gameManager.internalState.isSizeLocked = newValue }
    }
    var nextColor: StoneColor { gameManager.internalState.nextColor }
    var lastMove: (x: Int, y: Int)? { gameManager.internalState.lastMove }
    var moveCount: Int { gameManager.internalState.moveCount }
    var maxMoveCount: Int { gameManager.internalState.maxMoveCount }
    var variations: [Variation] { gameManager.internalState.variations }
    var treeNodes: [TreeVisualNode] { gameManager.internalState.treeNodes }
    var treeEdges: [TreeVisualEdge] { gameManager.internalState.treeEdges }
    var currentNodeId: String { gameManager.internalState.currentNodeId }
    var nodeComment: String { gameManager.internalState.nodeComment }
    var moveNumbers: [String: Int] { gameManager.internalState.moveNumbers }
    var metadata: GameMetadata { gameManager.internalState.metadata }

    // Settings with AppStorage for automatic persistence and reactivity
    @AppStorage("moveNumberDisplay") var moveNumberDisplay: MoveNumberDisplay = .all
    @AppStorage("showCoordinates") var showCoordinates: Bool = true
    @AppStorage("playSound") var playSound: Bool = true
    @AppStorage("boardSize") var persistedBoardSize: Int = 19
    @AppStorage("selectedThemeId") private var selectedThemeId: String = "wood"
    @AppStorage("lastSgfDirectory") private var lastSgfDirectoryPath: String = ""

    @Published var theme: BoardTheme = .defaultWood

    @Published var currentFileUrl: URL? = nil
    var lastSgfDirectory: URL? {
        get {
            lastSgfDirectoryPath.isEmpty ? nil : URL(fileURLWithPath: lastSgfDirectoryPath)
        }
        set {
            lastSgfDirectoryPath = newValue?.path ?? ""
        }
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
                lastAIPlayNodeId = nil
                aiManager.cancelPlay()
                updateAnalysis()
                stopClock()
            } else {
                aiPlayTask?.cancel()
                aiPlayTask = nil
                lastAIPlayNodeId = nil
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
    @Published var showResetConfirmation = false
    var clockTimer: Timer? = nil

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
    var lastAIPlayNodeId: String? = nil
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
        // Use UserDefaults directly in init to avoid 'self' access before full initialization
        let savedSize = UserDefaults.standard.integer(forKey: "boardSize")
        let initialSize = savedSize > 0 ? savedSize : 19

        self.gameManager = GameManager(initialSize: initialSize)
        self.aiManager = AIManager()

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
                    self?.resetClockForCurrentTurn()
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

    func placeStone(x: Int, y: Int, isAI: Bool = false) {
        if appMode == .play && !isAI {
            guard isHumanTurn else {
                SoundManager.shared.playAlert()
                return
            }
        }

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

    func toggleTheme() {
        selectedThemeId = (selectedThemeId == "wood") ? "bw" : "wood"
        theme = (selectedThemeId == "bw") ? .bwPrint : .defaultWood
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
