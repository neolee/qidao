import SwiftUI
import qidao_coreFFI

struct VariationTreeView: View {
    @ObservedObject var viewModel: BoardViewModel

    // Viewport offset management
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    let nodeSize: CGFloat = 8
    let spacingX: CGFloat = 16
    let spacingY: CGFloat = 20
    let padding: CGFloat = 30

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Background to catch drag gestures for panning
                Color.black.opacity(0.001)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                self.offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { value in
                                self.lastOffset = self.offset
                            }
                    )

                // High-performance drawing layer using Canvas
                Canvas { context, size in
                    drawTree(in: context)
                }
                .frame(width: treeContentWidth, height: treeContentHeight)
                .offset(offset)
                .gesture(SpatialTapGesture().onEnded { value in
                    handleTap(at: value.location)
                })
            }
            .onChange(of: viewModel.currentNodeId) { oldId, newId in
                centerCurrentNode(in: geometry.size)
            }
            .onAppear {
                centerCurrentNode(in: geometry.size)
            }
        }
        .clipped()
        .background(Color.black.opacity(0.02))
        .cornerRadius(8)
    }

    private var treeContentWidth: CGFloat {
        max(200, (viewModel.treeWidth * spacingX) + padding * 2)
    }

    private var treeContentHeight: CGFloat {
        max(200, (viewModel.treeHeight * spacingY) + padding * 2)
    }

    private func drawTree(in context: GraphicsContext) {
        // 1. Draw edges
        for edge in viewModel.treeEdges {
            var path = Path()
            path.move(to: CGPoint(
                x: edge.from.x * spacingX + padding,
                y: edge.from.y * spacingY + padding
            ))
            path.addLine(to: CGPoint(
                x: edge.to.x * spacingX + padding,
                y: edge.to.y * spacingY + padding
            ))
            context.stroke(path, with: .color(.gray.opacity(0.5)), lineWidth: 1)
        }

        // 2. Draw nodes
        for node in viewModel.treeNodes {
            let centerX = node.x * spacingX + padding
            let centerY = node.y * spacingY + padding
            let rect = CGRect(
                x: centerX - nodeSize/2,
                y: centerY - nodeSize/2,
                width: nodeSize,
                height: nodeSize
            )

            if node.id == viewModel.currentNodeId {
                // Current node: Blue Diamond (Drawn using Path for maximum compatibility)
                let s = nodeSize * 0.75
                var path = Path()
                path.move(to: CGPoint(x: centerX, y: centerY - s))
                path.addLine(to: CGPoint(x: centerX + s, y: centerY))
                path.addLine(to: CGPoint(x: centerX, y: centerY + s))
                path.addLine(to: CGPoint(x: centerX - s, y: centerY))
                path.closeSubpath()

                context.fill(path, with: .color(.blue))
                context.stroke(path, with: .color(.white), lineWidth: 1.5)
            } else {
                // Normal node: Circle
                let path = Path(ellipseIn: rect)
                let color = node.color == .black ? Color.black : (node.color == .white ? Color.white : Color.gray.opacity(0.4))
                context.fill(path, with: .color(color))
                context.stroke(path, with: .color(.black.opacity(0.2)), lineWidth: 0.5)
            }
        }
    }

    private func handleTap(at location: CGPoint) {
        let threshold: CGFloat = 15
        var closestNode: TreeVisualNode?
        var minDistance: CGFloat = .infinity

        for node in viewModel.treeNodes {
            let nodePos = CGPoint(x: node.x * spacingX + padding, y: node.y * spacingY + padding)
            let dist = location.distance(to: nodePos)
            if dist < minDistance {
                minDistance = dist
                closestNode = node
            }
        }

        if let closest = closestNode, minDistance < threshold {
            viewModel.jumpToNode(id: closest.id)
        }
    }

    private func centerCurrentNode(in viewportSize: CGSize) {
        guard let currentNode = viewModel.treeNodes.first(where: { $0.id == viewModel.currentNodeId }) else {
            return
        }

        let targetX = currentNode.x * spacingX + padding
        let targetY = currentNode.y * spacingY + padding

        let newOffset = CGSize(
            width: viewportSize.width / 2 - targetX,
            height: viewportSize.height / 2 - targetY
        )

        withAnimation(.easeInOut(duration: 0.3)) {
            self.offset = newOffset
            self.lastOffset = newOffset
        }
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        sqrt(pow(x - other.x, 2) + pow(y - other.y, 2))
    }
}

struct VariationMarker: View {
    let label: String
    let theme: BoardTheme
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: size * 0.5, height: size * 0.5)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 1)

            Text(label)
                .font(.system(size: size * 0.3, weight: .bold))
                .foregroundColor(.white)
        }
    }
}
