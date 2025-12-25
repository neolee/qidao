import SwiftUI

struct BoardView: View {
    @StateObject private var viewModel = BoardViewModel()
    private let boardSize: CGFloat = 500
    private let gridSize: Int = 19

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("QiDao")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                Spacer()
                Text("Next: \(viewModel.nextColor == .black ? "Black" : "White")")
                    .padding(8)
                    .background(viewModel.nextColor == .black ? Color.black : Color.white)
                    .foregroundColor(viewModel.nextColor == .black ? Color.white : Color.black)
                    .cornerRadius(8)
                    .shadow(radius: 2)
            }
            .padding(.horizontal)

            // High-performance Board Rendering
            ZStack {
                // 1. Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.85, green: 0.65, blue: 0.45))
                    .shadow(radius: 10)

                // 2. Grid Lines
                BoardGrid(gridSize: gridSize)
                    .stroke(Color.black.opacity(0.8), lineWidth: 1)

                // 3. Star Points (Hoshi)
                StarPoints(gridSize: gridSize)
                    .fill(Color.black)

                // 4. Stones
                GeometryReader { geometry in
                    let spacing = geometry.size.width / CGFloat(gridSize + 1)

                    ForEach(0..<gridSize, id: \.self) { y in
                        ForEach(0..<gridSize, id: \.self) { x in
                            if let color = viewModel.board.getStone(x: UInt32(x), y: UInt32(y)) {
                                StoneView(color: color, size: spacing * 0.9)
                                    .position(
                                        x: CGFloat(x + 1) * spacing,
                                        y: CGFloat(y + 1) * spacing
                                    )
                            }
                        }
                    }
                }
            }
            .frame(width: boardSize, height: boardSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let spacing = boardSize / CGFloat(gridSize + 1)
                        let x = Int(round(value.location.x / spacing)) - 1
                        let y = Int(round(value.location.y / spacing)) - 1

                        if x >= 0 && x < gridSize && y >= 0 && y < gridSize {
                            viewModel.placeStone(x: x, y: y)
                        }
                    }
            )

            VStack(spacing: 10) {
                Text(viewModel.message)
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack {
                    Button("Reset Board") {
                        viewModel.resetBoard()
                    }
                    .buttonStyle(.bordered)

                    Button("Run Core Test") {
                        viewModel.testCore()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 700)
    }
}

// MARK: - Subviews

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

        let points: [Int] = gridSize == 19 ? [3, 9, 15] : [3, gridSize/2, gridSize-4]

        for row in points {
            for col in points {
                let center = CGPoint(x: CGFloat(col + 1) * spacing, y: CGFloat(row + 1) * spacing)
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
        }
        return path
    }
}

struct StoneView: View {
    let color: StoneColor
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color == .black ?
                  AnyShapeStyle(RadialGradient(colors: [.gray, .black], center: .topLeading, startRadius: 2, endRadius: size)) :
                  AnyShapeStyle(RadialGradient(colors: [.white, .gray.opacity(0.3)], center: .topLeading, startRadius: 2, endRadius: size))
            )
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
    }
}

#Preview {
    BoardView()
}
