import Foundation
import Combine

class BoardViewModel: ObservableObject {
    @Published var message: String = "Waiting for Core..."
    @Published var gameInfo: String = ""

    func testCore() {
        // Call the 'add' function from Rust
        // Note: UniFFI uses UInt32 for u32
        let result = add(a: 10, b: 32)
        message = "Core Test: 10 + 32 = \(result)"

        // Call 'getSampleGame' from Rust (UniFFI converts snake_case to camelCase)
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
    }
}
