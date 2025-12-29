import SwiftUI
import qidao_coreFFI

struct StoneView: View {
    let color: StoneColor
    let theme: BoardTheme
    let size: CGFloat
    let moveNumber: Int?
    let markerType: MarkerType?
    var fontSize: CGFloat? = nil

    var body: some View {
        let style = (color == .black) ? theme.blackStoneStyle : theme.whiteStoneStyle

        ZStack {
            // 1. Stone Shadow (3D effect)
            Circle()
                .fill(style.shadowColor)
                .offset(x: 1.5, y: 2.0)
                .frame(width: size, height: size)
                .blur(radius: 5)

            // 2. Stone Body
            Circle()
                .fill(style.fill)
                .frame(width: size, height: size)

            // 3. Subtle 3D Highlight
            if style.hasHighlight {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(color == .black ? 0.3 : 0.6),
                                .clear
                            ],
                            center: .init(x: 0.3, y: 0),
                            startRadius: 0,
                            endRadius: size * 0.5
                        )
                    )
                    .frame(width: size, height: size)
            }

            // 4. Stroke (if any)
            if style.strokeWidth > 0 {
                Circle()
                    .stroke(style.strokeColor, lineWidth: style.strokeWidth)
                    .frame(width: size, height: size)
            }

            // 5. Move Number or Marker
            if let num = moveNumber {
                Text("\(num)")
                    .font(.system(size: fontSize ?? (size * 0.4), weight: .bold))
                    .foregroundColor(style.textColor)
            } else if let marker = markerType {
                switch marker {
                case .last1:
                    // Hollow circle, half radius
                    Circle()
                        .stroke(style.textColor, lineWidth: 2)
                        .frame(width: size * 0.5, height: size * 0.5)
                case .last2, .last3:
                    // Small solid circle, 1/4 radius
                    Circle()
                        .fill(style.textColor)
                        .frame(width: size * 0.25, height: size * 0.25)
                }
            }
        }
    }
}

struct BoardGrid: Shape {
    let gridSize: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing = rect.width / CGFloat(gridSize + 1)

        for i in 1...gridSize {
            // Vertical lines
            path.move(to: CGPoint(x: CGFloat(i) * spacing, y: spacing))
            path.addLine(to: CGPoint(x: CGFloat(i) * spacing, y: rect.height - spacing))

            // Horizontal lines
            path.move(to: CGPoint(x: spacing, y: CGFloat(i) * spacing))
            path.addLine(to: CGPoint(x: rect.width - spacing, y: CGFloat(i) * spacing))
        }

        return path
    }
}

struct StarPoints: Shape {
    let gridSize: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing = rect.width / CGFloat(gridSize + 1)
        let radius: CGFloat = 3

        let points: [Int]
        if gridSize == 19 {
            points = [4, 10, 16]
        } else if gridSize == 13 {
            points = [4, 7, 10]
        } else if gridSize == 9 {
            points = [3, 5, 7]
        } else {
            points = []
        }

        for row in points {
            for col in points {
                let center = CGPoint(x: CGFloat(col) * spacing, y: CGFloat(row) * spacing)
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
        }

        return path
    }
}

struct BoardCoordinates: View {
    let gridSize: Int
    let spacing: CGFloat

    private let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T"]

    var body: some View {
        ZStack {
            // Top & Bottom (Letters)
            ForEach(0..<gridSize, id: \.self) { i in
                Text(letters[i])
                    .font(.system(size: spacing * 0.3, weight: .medium))
                    .position(x: CGFloat(i + 1) * spacing, y: spacing * 0.4)

                Text(letters[i])
                    .font(.system(size: spacing * 0.3, weight: .medium))
                    .position(x: CGFloat(i + 1) * spacing, y: CGFloat(gridSize + 1) * spacing - spacing * 0.4)
            }

            // Left & Right (Numbers)
            ForEach(0..<gridSize, id: \.self) { i in
                let label = "\(gridSize - i)"
                Text(label)
                    .font(.system(size: spacing * 0.3, weight: .medium))
                    .position(x: spacing * 0.4, y: CGFloat(i + 1) * spacing)

                Text(label)
                    .font(.system(size: spacing * 0.3, weight: .medium))
                    .position(x: CGFloat(gridSize + 1) * spacing - spacing * 0.4, y: CGFloat(i + 1) * spacing)
            }
        }
    }
}

struct VariationMarker: View {
    let label: String
    let theme: BoardTheme
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.4))
                .frame(width: size * 0.6, height: size * 0.6)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 2)

            Text(label)
                .font(.system(size: size * 0.35, weight: .black))
                .foregroundColor(.white)
        }
    }
}

struct AIMoveMarker: View {
    let winRate: Double
    let scoreLead: Double
    let visits: Int
    let rank: Int
    let color: Color
    let textColor: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.7))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)

            VStack(spacing: -0.2) {
                // 1. Visits (Top, Small)
                Text("\(visits)")
                    .font(.system(size: size * 0.22, weight: .medium))
                    .foregroundColor(textColor.opacity(0.85))

                // 2. Win Rate (Center, Large)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(String(format: "%.1f", winRate * 100))
                        .font(.system(size: size * 0.32, weight: .bold))
                    Text("%")
                        .font(.system(size: size * 0.16, weight: .bold))
                }
                .foregroundColor(textColor)
                .padding(.vertical, -2)

                // 3. Score Lead (Bottom, Small)
                Text(String(format: "%+.1f", scoreLead))
                    .font(.system(size: size * 0.22, weight: .medium))
                    .foregroundColor(textColor.opacity(0.85))
            }

            // Rank number at top-right
            if rank <= 9 {
                Text("\(rank)")
                    .font(.system(size: size * 0.22, weight: .black))
                    .foregroundColor(textColor)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .background(
                        RoundedRectangle(cornerRadius: size * 0.08)
                            .fill(Color.black.opacity(0.6))
                            .overlay(RoundedRectangle(cornerRadius: size * 0.08).stroke(textColor.opacity(0.5), lineWidth: 0.5))
                    )
                    .offset(x: size * 0.4, y: -size * 0.4)
            }
        }
    }
}

struct MarkerView: View {
    let type: String
    let label: String?
    let theme: BoardTheme
    let size: CGFloat
    let stoneColor: StoneColor?

    var body: some View {
        let color: Color = {
            if let stoneColor = stoneColor {
                return stoneColor == .black ? theme.blackStoneStyle.textColor : theme.whiteStoneStyle.textColor
            }
            return theme.lineColor
        }()

        ZStack {
            // Background mask for marks on empty intersections
            if stoneColor == nil {
                Circle()
                    .fill(theme.boardColor)
                    .frame(width: size * 0.6, height: size * 0.6)
            }

            Group {
                switch type {
                case "TR":
                    Triangle()
                        .stroke(color, lineWidth: 2)
                        .frame(width: size * 0.5, height: size * 0.43) // Closer to equilateral
                case "CR":
                    Circle()
                        .stroke(color, lineWidth: 2)
                        .frame(width: size * 0.5, height: size * 0.5)
                case "SQ":
                    Rectangle()
                        .stroke(color, lineWidth: 2)
                        .frame(width: size * 0.45, height: size * 0.45)
                case "MA":
                    Cross()
                        .stroke(color, lineWidth: 2)
                        .frame(width: size * 0.45, height: size * 0.45)
                case "LB":
                    if let label = label {
                        Text(label)
                            .font(.system(size: size * 0.5, weight: .bold))
                            .foregroundColor(color)
                    }
                default:
                    EmptyView()
                }
            }
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct Cross: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}
