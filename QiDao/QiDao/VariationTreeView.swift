import SwiftUI
import qidao_coreFFI

struct VariationTreeView: View {
    @ObservedObject var viewModel: BoardViewModel
    let nodeSize: CGFloat = 8
    let spacingX: CGFloat = 16
    let spacingY: CGFloat = 20
    let padding: CGFloat = 30

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    // High-performance drawing layer using Canvas
                    Canvas { context, size in
                        drawTree(in: context)
                    }
                    .frame(width: treeContentWidth, height: treeContentHeight)
                    .gesture(SpatialTapGesture().onEnded { value in
                        handleTap(at: value.location)
                    })

                    // Invisible anchor for auto-scrolling
                    if let currentNode = viewModel.treeNodes.first(where: { $0.id == viewModel.currentNodeId }) {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .position(
                                x: currentNode.x * spacingX + padding,
                                y: currentNode.y * spacingY + padding
                            )
                            .id("scroll_anchor")
                    }
                }
            }
            .onChange(of: viewModel.currentNodeId) { oldId, newId in
                scrollToCurrent(proxy: proxy)
            }
            .onAppear {
                scrollToCurrent(proxy: proxy)
            }
        }
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

    private func scrollToCurrent(proxy: ScrollViewProxy) {
        // Use async to ensure the anchor position is updated before scrolling
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                // Using .center anchor ensures the node is centered both horizontally and vertically
                proxy.scrollTo("scroll_anchor", anchor: .center)
            }
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
        Circle()
            .fill(Color.gray.opacity(0.5))
            .frame(width: size * 0.5, height: size * 0.5)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 1)
    }
}
