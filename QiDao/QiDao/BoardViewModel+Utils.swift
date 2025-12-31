import Foundation
import qidao_coreFFI

extension BoardViewModel {
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

    func getHandicapStones(size: Int, count: Int) -> [(Int, Int)] {
        let edge = size >= 13 ? 3 : 2
        let mid = size / 2
        let far = size - 1 - edge

        var points: [(Int, Int)] = []

        // Standard handicap points
        let p1 = (far, edge)  // Top Right
        let p2 = (edge, far)  // Bottom Left
        let p3 = (far, far)   // Bottom Right
        let p4 = (edge, edge) // Top Left
        let p5 = (mid, mid)   // Center
        let p6 = (edge, mid)  // Left Mid
        let p7 = (far, mid)   // Right Mid
        let p8 = (mid, edge)  // Top Mid
        let p9 = (mid, far)   // Bottom Mid

        switch count {
        case 2: points = [p1, p2]
        case 3: points = [p1, p2, p3]
        case 4: points = [p1, p2, p3, p4]
        case 5: points = [p1, p2, p3, p4, p5]
        case 6: points = [p1, p2, p3, p4, p6, p7]
        case 7: points = [p1, p2, p3, p4, p6, p7, p5]
        case 8: points = [p1, p2, p3, p4, p6, p7, p8, p9]
        case 9: points = [p1, p2, p3, p4, p6, p7, p8, p9, p5]
        default: break
        }

        return points
    }
}
