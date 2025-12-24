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
    }
}
