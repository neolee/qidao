import Foundation
import SwiftUI
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

struct GameState {
    var board: Board = Board(size: 19)
    var boardSize: Int = 19
    var isSizeLocked: Bool = false
    var nextColor: StoneColor = .black
    var lastMove: (x: Int, y: Int)? = nil
    var moveCount: Int = 0
    var maxMoveCount: Int = 0
    var variations: [Variation] = []
    var treeNodes: [TreeVisualNode] = []
    var treeEdges: [TreeVisualEdge] = []
    var currentNodeId: String = ""
    var moveNumbers: [String: Int] = [:]
    var metadata: GameMetadata = GameMetadata(
        blackName: "", blackRank: "",
        whiteName: "", whiteRank: "",
        komi: 7.5, result: "",
        date: "", event: "",
        gameName: "", place: "",
        size: 19
    )
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

extension BoardViewModel {
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let message: String
        let isError: Bool
        let isCommunication: Bool
    }

    enum BlunderType: String {
        case blunder // > 15% drop
    }
}
