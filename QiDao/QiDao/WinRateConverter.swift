import Foundation

/// Utility for translating KataGo win rate and score lead values between reporting perspectives.
struct WinRateConverter {
    /// Converts a win rate value reported with a given perspective into a target perspective.
    static func convertWinRate(_ value: Double, reportedAs: WinRatePerspective, target: WinRatePerspective, isWhiteTurn: Bool) -> Double {
        let blackPerspective: Double
        switch reportedAs {
        case .black:
            blackPerspective = value
        case .current:
            blackPerspective = isWhiteTurn ? (1.0 - value) : value
        }

        switch target {
        case .black:
            return blackPerspective
        case .current:
            return isWhiteTurn ? (1.0 - blackPerspective) : blackPerspective
        }
    }

    /// Converts a score lead value reported with a given perspective into a target perspective.
    static func convertScoreLead(_ value: Double, reportedAs: WinRatePerspective, target: WinRatePerspective, isWhiteTurn: Bool) -> Double {
        let blackPerspective: Double
        switch reportedAs {
        case .black:
            blackPerspective = value
        case .current:
            blackPerspective = isWhiteTurn ? -value : value
        }

        switch target {
        case .black:
            return blackPerspective
        case .current:
            return isWhiteTurn ? -blackPerspective : blackPerspective
        }
    }
}
