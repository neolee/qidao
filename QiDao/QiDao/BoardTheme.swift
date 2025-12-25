import SwiftUI

struct BoardTheme: Identifiable {
    let id: String
    let name: String
    let boardColor: Color
    let lineColor: Color
    let starPointColor: Color
    let lastMoveMarkerColor: Color
    let gridLineWidth: CGFloat
    let blackStoneStyle: StoneStyle
    let whiteStoneStyle: StoneStyle

    struct StoneStyle {
        let fill: AnyShapeStyle
        let textColor: Color
        let shadowColor: Color
        let strokeColor: Color
        let strokeWidth: CGFloat
        let markerColor: Color
        let hasHighlight: Bool
    }

    static let defaultWood = BoardTheme(
        id: "wood",
        name: "Default Wood",
        boardColor: Color(red: 0.90, green: 0.70, blue: 0.49), // #e6b37e
        lineColor: Color(red: 0.27, green: 0.20, blue: 0.13), // #443322
        starPointColor: Color(red: 0.27, green: 0.20, blue: 0.13),
        lastMoveMarkerColor: Color.red,
        gridLineWidth: 0.6,
        blackStoneStyle: StoneStyle(
            fill: AnyShapeStyle(Color(white: 0.1)),
            textColor: .white.opacity(0.9),
            shadowColor: .black.opacity(0.6),
            strokeColor: .black.opacity(0.8),
            strokeWidth: 0.5,
            markerColor: .white,
            hasHighlight: true
        ),
        whiteStoneStyle: StoneStyle(
            fill: AnyShapeStyle(Color(white: 0.9)),
            textColor: .black.opacity(0.8),
            shadowColor: .black.opacity(0.4),
            strokeColor: Color(white: 0.8),
            strokeWidth: 0.5,
            markerColor: .black,
            hasHighlight: true
        )
    )

    static let bwPrint = BoardTheme(
        id: "bw",
        name: "B&W Print",
        boardColor: .white,
        lineColor: .black,
        starPointColor: .black,
        lastMoveMarkerColor: .black.opacity(0.8),
        gridLineWidth: 0.4,
        blackStoneStyle: StoneStyle(
            fill: AnyShapeStyle(Color.black),
            textColor: .white,
            shadowColor: .clear,
            strokeColor: .clear,
            strokeWidth: 0,
            markerColor: .white,
            hasHighlight: false
        ),
        whiteStoneStyle: StoneStyle(
            fill: AnyShapeStyle(Color.white),
            textColor: .black,
            shadowColor: .clear,
            strokeColor: .black,
            strokeWidth: 1.0,
            markerColor: .black,
            hasHighlight: false
        )
    )
}
