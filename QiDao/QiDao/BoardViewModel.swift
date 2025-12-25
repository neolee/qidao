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
    @Published var metadata: GameMetadata = GameMetadata(
        blackName: "", blackRank: "",
        whiteName: "", whiteRank: "",
        komi: 7.5, result: "",
        date: "", event: "",
        gameName: "", place: "",
        size: 19
    )

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
    private var moveCount: Int = 0

    init() {
        // Initialize Game Controller
        self.game = Game(size: 19)

        // Load persisted settings
        self.showMoveNumbers = UserDefaults.standard.object(forKey: "showMoveNumbers") as? Bool ?? true
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
        syncStateWithGame()
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
            let oldStoneCount = countStones(on: board)

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

            syncStateWithGame()
        } catch {
            self.message = "\("Invalid Move".localized): \(error)"
        }
    }

    func goBack() {
        if game.goBack() {
            // When going back, for consistency with most Go apps, we play a stone sound.
            SoundManager.shared.play(name: "stone")

            syncStateWithGame()
        }
    }

    func goForward() {
        let oldStoneCount = countStones(on: board)
        if game.goForward(index: 0) { // Default to first branch
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

    private func syncStateWithGame() {
        // Ensure updates happen on main thread and outside immediate view update cycle
        DispatchQueue.main.async {
            self.board = self.game.getBoard()
            self.nextColor = self.game.getNextColor()
            self.moveCount = Int(self.game.getMoveCount())
            self.metadata = self.game.getMetadata()

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

            self.refreshMessage()
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
        self.game = Game(size: 19)
        syncStateWithGame()
        self.message = "Board Reset".localized
    }

    func toggleTheme() {
        theme = (theme.id == "wood") ? .bwPrint : .defaultWood
        UserDefaults.standard.set(theme.id, forKey: "selectedThemeId")
    }

    func updateMetadata(_ newMetadata: GameMetadata) {
        game.setMetadata(metadata: newMetadata)
        syncStateWithGame()
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
            syncStateWithGame()
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
}
