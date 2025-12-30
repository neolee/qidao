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

enum AppMode: String, CaseIterable, Identifiable {
    case analysis
    case edit
    case play

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .analysis: return "Analysis Mode".localized
        case .edit: return "Edit Mode".localized
        case .play: return "Play Mode".localized
        }
    }
}

enum EditTool: String, CaseIterable, Identifiable {
    case stoneBlack
    case stoneWhite
    case stoneAuto
    case markTriangle
    case markCircle
    case markSquare
    case markCross
    case markLabel
    case clear

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .stoneBlack: return "circle.fill"
        case .stoneWhite: return "circle"
        case .stoneAuto: return "circle.badge.plus"
        case .markTriangle: return "triangle"
        case .markCircle: return "circle"
        case .markSquare: return "square"
        case .markCross: return "xmark"
        case .markLabel: return "character.textbox"
        case .clear: return "eraser"
        }
    }

    var label: String {
        switch self {
        case .stoneBlack: return "Black Stone".localized
        case .stoneWhite: return "White Stone".localized
        case .stoneAuto: return "Auto Stone".localized
        case .markTriangle: return "Triangle".localized
        case .markCircle: return "Circle".localized
        case .markSquare: return "Square".localized
        case .markCross: return "Cross".localized
        case .markLabel: return "Label".localized
        case .clear: return "Clear".localized
        }
    }

    var markType: String? {
        switch self {
        case .markTriangle: return "TR"
        case .markCircle: return "CR"
        case .markSquare: return "SQ"
        case .markCross: return "MA"
        case .markLabel: return "LB"
        default: return nil
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

struct BoardMark: Identifiable {
    let id = UUID()
    let x: Int
    let y: Int
    let type: String // "TR", "CR", "SQ", "MA", "LB"
    let label: String?
}

struct GameState {
    var board: Board = Board(size: 19)
    var boardSize: Int = 19
    var isSizeLocked: Bool = false
    var nextColor: StoneColor = .black
    var initialColor: StoneColor = .black
    var lastMove: (x: Int, y: Int)? = nil
    var moveCount: Int = 0
    var maxMoveCount: Int = 0
    var variations: [Variation] = []
    var treeNodes: [TreeVisualNode] = []
    var treeEdges: [TreeVisualEdge] = []
    var currentNodeId: String = ""
    var nodeComment: String = ""
    var moveNumbers: [String: Int] = [:]
    var sgf: String = ""
    var metadata: GameMetadata = GameMetadata(
        blackName: "", blackRank: "",
        whiteName: "", whiteRank: "",
        komi: 7.5, result: "",
        date: "", event: "",
        gameName: "", place: "",
        size: 19
    )
    var marks: [BoardMark] = []
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

enum AIStatus: String {
    case idle
    case starting
    case ready
    case analyzing
    case thinking
    case error

    var icon: String {
        switch self {
        case .idle: return "power"
        case .starting: return "arrow.clockwise.circle"
        case .ready: return "checkmark.circle"
        case .analyzing: return "magnifyingglass.circle"
        case .thinking: return "brain.head.profile"
        case .error: return "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .secondary
        case .starting: return .blue
        case .ready: return .green
        case .analyzing: return .blue
        case .thinking: return .orange
        case .error: return .red
        }
    }
}

enum LogType: String {
    case info
    case warning
    case error
    case play      // Slot A: Play mode
    case analysis  // Slot B: Interactive analysis
    case fullScan  // Slot C: Background full game scan
    case raw       // For developer mode
}

struct EngineLog: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let type: LogType
}

enum AIRole: String, CaseIterable, Identifiable {
    case manual
    case black
    case white
    case both

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .manual: return "Manual".localized
        case .black: return "AI Black".localized
        case .white: return "AI White".localized
        case .both: return "Both".localized
        }
    }

    var icon: String {
        switch self {
        case .manual: return "person"
        case .black: return "cpu"
        case .white: return "cpu.fill"
        case .both: return "bolt.fill"
        }
    }
}

extension BoardViewModel {
    enum BlunderType: String {
        case blunder // > 15% drop
    }
}
