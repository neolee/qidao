import Foundation
import qidao_coreFFI
import Combine

@MainActor
class GameManager: ObservableObject {
    @Published var internalState = GameState()
    @Published var gameState = GameState()

    private var game: Game
    private var nodeMap: [String: SgfNode] = [:]

    init(initialSize: Int) {
        self.game = Game(size: UInt32(initialSize))
        self.internalState.boardSize = initialSize
        self.internalState.metadata.size = UInt32(initialSize)
        syncState(rebuildTree: true)
    }

    func getGame() -> Game { game }
    func setGame(_ newGame: Game) {
        self.game = newGame
        syncState(rebuildTree: true)
    }

    func placeStone(x: Int, y: Int, color: StoneColor) throws -> Int {
        let currentBoard = game.getBoard()
        let oldStoneCount = countStones(on: currentBoard)

        try game.placeStone(x: UInt32(x), y: UInt32(y), color: color)

        let newBoard = game.getBoard()
        let newStoneCount = countStones(on: newBoard)

        let captures = oldStoneCount + 1 - newStoneCount
        syncState(rebuildTree: true)
        return captures
    }

    func goBack() -> Bool {
        if game.goBack() {
            syncState()
            return true
        }
        return false
    }

    func goForward(index: Int = 0) -> Int? {
        let currentBoard = game.getBoard()
        let oldStoneCount = countStones(on: currentBoard)
        if game.goForward(index: UInt32(index)) {
            let newBoard = game.getBoard()
            let newStoneCount = countStones(on: newBoard)
            let captures = oldStoneCount + 1 - newStoneCount
            syncState()
            return captures
        }
        return nil
    }

    func jumpToMove(_ target: Int) {
        game.jumpToMoveNumber(target: UInt32(target))
        syncState()
    }

    func jumpToNode(id: String) {
        if let node = nodeMap[id] {
            game.jumpToNode(target: node)
            syncState()
        }
    }

    func deleteCurrentBranch() -> Bool {
        if game.deleteCurrentBranch() {
            syncState(rebuildTree: true)
            return true
        }
        return false
    }

    func reset(size: Int) {
        self.game = Game(size: UInt32(size))
        syncState(rebuildTree: true)
    }

    func updateMetadata(_ newMetadata: GameMetadata) {
        game.setMetadata(metadata: newMetadata)
        syncState(rebuildTree: true)
    }

    func syncState(rebuildTree: Bool = false) {
        var newState = internalState
        newState.board = self.game.getBoard()
        newState.nextColor = self.game.getNextColor()
        newState.moveCount = Int(self.game.getMoveCount())
        newState.maxMoveCount = Int(self.game.getMaxMoveCount())
        newState.metadata = self.game.getMetadata()
        newState.currentNodeId = self.game.getCurrentNode().getId()
        newState.nodeComment = self.game.getComment()
        newState.sgf = self.game.toSgf()

        newState.boardSize = Int(newState.metadata.size)
        newState.isSizeLocked = newState.isSizeLocked || newState.moveCount > 0 || self.game.getMaxMoveCount() > 0

        if let last = self.game.getLastMove(), let coords = last.values.first, coords.count == 2 {
            let x = Int(coords.first!.asciiValue! - UInt8(ascii: "a"))
            let y = Int(coords.last!.asciiValue! - UInt8(ascii: "a"))
            newState.lastMove = (x, y)
        } else {
            newState.lastMove = nil
        }

        newState.moveNumbers = [:]
        let pathMoves = self.game.getCurrentPathMoves()
        for (index, moveProp) in pathMoves.enumerated() {
            if let coords = moveProp.values.first, coords.count == 2 {
                let x = Int(coords.first!.asciiValue! - UInt8(ascii: "a"))
                let y = Int(coords.last!.asciiValue! - UInt8(ascii: "a"))
                newState.moveNumbers["\(x),\(y)"] = index + 1
            }
        }

        newState.marks = []
        let currentProps = self.game.getCurrentNode().getProperties()
        for prop in currentProps {
            if ["TR", "CR", "SQ", "MA"].contains(prop.identifier) {
                for val in prop.values {
                    if val.count == 2 {
                        let x = Int(val.first!.asciiValue! - UInt8(ascii: "a"))
                        let y = Int(val.last!.asciiValue! - UInt8(ascii: "a"))
                        newState.marks.append(BoardMark(x: x, y: y, type: prop.identifier, label: nil))
                    }
                }
            } else if prop.identifier == "LB" {
                for val in prop.values {
                    let parts = val.split(separator: ":")
                    if parts.count == 2, let coords = parts.first, coords.count == 2 {
                        let x = Int(coords.first!.asciiValue! - UInt8(ascii: "a"))
                        let y = Int(coords.last!.asciiValue! - UInt8(ascii: "a"))
                        let label = String(parts.last!)
                        newState.marks.append(BoardMark(x: x, y: y, type: "LB", label: label))
                    }
                }
            }
        }

        let children = self.game.getCurrentNode().getChildren()
        let variationChildren = children.count > 1 ? children : []
        newState.variations = variationChildren.enumerated().map { (index, node) in
            let props = node.getProperties()
            let moveProp = props.first { $0.identifier == "B" || $0.identifier == "W" }
            var vx: Int? = nil
            var vy: Int? = nil
            let moveText: String
            if let prop = moveProp, let coords = prop.values.first, coords.count == 2 {
                vx = Int(coords.first!.asciiValue! - UInt8(ascii: "a"))
                vy = Int(coords.last!.asciiValue! - UInt8(ascii: "a"))
                moveText = "\(prop.identifier) (\(vx!), \(vy!))"
            } else {
                moveText = "Node \(index + 1)"
            }
            return Variation(id: index, moveText: moveText, x: vx, y: vy)
        }

        if rebuildTree {
            let tree = self.rebuildTreeInternal()
            newState.treeNodes = tree.nodes
            newState.treeEdges = tree.edges
        }

        self.internalState = newState

        // Update gameState asynchronously for UI
        DispatchQueue.main.async {
            self.gameState = newState
        }
    }

    private func rebuildTreeInternal() -> (nodes: [TreeVisualNode], edges: [TreeVisualEdge]) {
        nodeMap = [:]
        var nodes: [TreeVisualNode] = []
        var edges: [TreeVisualEdge] = []

        let root = game.getRootNode()
        var nextXAtDepth: [Int: Int] = [:]

        func traverse(node: SgfNode, depth: Int, xOffset: Int, parentPos: CGPoint?) {
            let id = node.getId()
            nodeMap[id] = node

            let x = CGFloat(xOffset)
            let y = CGFloat(depth)
            let currentPos = CGPoint(x: x, y: y)

            let props = node.getProperties()
            var color: StoneColor? = nil
            if props.contains(where: { $0.identifier == "B" }) {
                color = .black
            } else if props.contains(where: { $0.identifier == "W" }) {
                color = .white
            }

            nodes.append(TreeVisualNode(id: id, x: x, y: y, color: color))

            if let parent = parentPos {
                edges.append(TreeVisualEdge(id: "\(id)-edge", from: parent, to: currentPos))
            }

            let children = node.getChildren()
            let currentX = xOffset
            for (index, child) in children.enumerated() {
                let childX = (index == 0) ? currentX : (nextXAtDepth[depth + 1] ?? currentX + 1)
                nextXAtDepth[depth + 1] = max(nextXAtDepth[depth + 1] ?? 0, childX + 1)
                traverse(node: child, depth: depth + 1, xOffset: childX, parentPos: currentPos)
            }
        }

        traverse(node: root, depth: 0, xOffset: 0, parentPos: nil)
        return (nodes, edges)
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
}
