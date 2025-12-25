import Foundation
import Combine
import qidao_coreFFI

class BoardViewModel: ObservableObject {
    @Published var message: String = "Ready".localized
    @Published var gameInfo: String = ""
    @Published var board: Board = Board(size: 19)
    @Published var nextColor: StoneColor = .black
    @Published var theme: BoardTheme = .defaultWood
    @Published var showMoveNumbers: Bool = true {
        didSet { UserDefaults.standard.set(showMoveNumbers, forKey: "showMoveNumbers") }
    }
    @Published var showCoordinates: Bool = true {
        didSet { UserDefaults.standard.set(showCoordinates, forKey: "showCoordinates") }
    }
    @Published var playSound: Bool = true {
        didSet { UserDefaults.standard.set(playSound, forKey: "playSound") }
    }
    @Published var lastMove: (x: Int, y: Int)? = nil
    
    var langManager = LanguageManager.shared

    // Track move history for numbering
    @Published var moveNumbers: [String: Int] = [:]
    private var moveCount: Int = 0

    init() {
        // Load persisted settings
        self.showMoveNumbers = UserDefaults.standard.object(forKey: "showMoveNumbers") as? Bool ?? true
        self.showCoordinates = UserDefaults.standard.object(forKey: "showCoordinates") as? Bool ?? true
        self.playSound = UserDefaults.standard.object(forKey: "playSound") as? Bool ?? true
        
        let themeId = UserDefaults.standard.string(forKey: "selectedThemeId") ?? "wood"
        self.theme = (themeId == "bw") ? .bwPrint : .defaultWood
    }

    func placeStone(x: Int, y: Int) {
        do {
            let color = nextColor
            let oldStoneCount = countStones(on: board)
            let newBoard = try board.placeStone(x: UInt32(x), y: UInt32(y), color: color)
            let newStoneCount = countStones(on: newBoard)
            
            // Play sound based on captures
            // newStoneCount = oldStoneCount + 1 - captures
            // captures = oldStoneCount + 1 - newStoneCount
            let captures = oldStoneCount + 1 - newStoneCount
            
            if captures == 0 {
                SoundManager.shared.play(name: "stone")
            } else if captures == 1 {
                SoundManager.shared.play(name: "dead-stone")
            } else {
                SoundManager.shared.play(name: "dead-stones")
            }

            self.board = newBoard
            self.nextColor = (color == .black) ? .white : .black
            self.lastMove = (x, y)

            moveCount += 1
            moveNumbers["\(x),\(y)"] = moveCount

            let colorStr = (color == .black ? "Black" : "White").localized
            self.message = "\("Move".localized) \(moveCount): \(colorStr) at (\(x), \(y))"
        } catch {
            self.message = "\("Invalid Move".localized): \(error)"
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

    func resetBoard() {
        self.board = Board(size: 19)
        self.nextColor = .black
        self.moveNumbers = [:]
        self.moveCount = 0
        self.lastMove = nil
        self.message = "Board Reset".localized
    }

    func toggleTheme() {
        theme = (theme.id == "wood") ? .bwPrint : .defaultWood
        UserDefaults.standard.set(theme.id, forKey: "selectedThemeId")
    }

    func testCore() {
        // Call the 'add' function from Rust
        let result = add(a: 10, b: 32)
        message = "Core Test: 10 + 32 = \(result)"

        // Call 'getSampleGame' from Rust
        let info = getSampleGame()
        gameInfo = "Game: \(info.blackPlayer) vs \(info.whitePlayer) (Komi: \(info.komi))"

        // Test SGF Parsing
        let sgf = "(;GM[1]FF[4]CA[UTF-8]AP[QiDao]KM[7.5]PB[Black]PW[White];B[pd];W[dp])"
        do {
            let tree = try parseSgf(sgfContent: sgf)
            let root = tree.root()
            let children = root.getChildren()
            message += "\nSGF Parsed: \(children.count) moves in main branch."
        } catch {
            message += "\nSGF Parse Error: \(error)"
        }

        // Test Board Logic
        let newBoard = Board(size: 19)
        do {
            // Place a black stone at (3, 3) - 4-4 point
            let boardAfterBlack = try newBoard.placeStone(x: 3, y: 3, color: .black)
            // Place a white stone at (15, 15)
            let boardAfterWhite = try boardAfterBlack.placeStone(x: 15, y: 15, color: .white)

            self.board = boardAfterWhite
            message += "\nBoard Test: Stones placed at (3,3) and (15,15)."

            if let stone = boardAfterWhite.getStone(x: 3, y: 3) {
                message += "\nStone at (3,3) is \(stone == .black ? "Black" : "White")"
            }
        } catch {
            message += "\nBoard Error: \(error)"
        }
    }
}
