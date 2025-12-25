import SwiftUI
import qidao_coreFFI

struct VariationTreeView: View {
    @ObservedObject var viewModel: BoardViewModel
    let nodeSize: CGFloat = 8
    let spacingX: CGFloat = 16
    let spacingY: CGFloat = 20

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    // Draw edges
                    ForEach(viewModel.treeEdges) { edge in
                        TreeEdgeView(edge: edge, spacingX: spacingX, spacingY: spacingY, nodeSize: nodeSize)
                    }

                    // Draw nodes
                    ForEach(viewModel.treeNodes) { node in
                        TreeNodeView(
                            node: node,
                            isCurrent: node.id == viewModel.currentNodeId,
                            spacingX: spacingX,
                            spacingY: spacingY,
                            nodeSize: nodeSize
                        ) {
                            viewModel.jumpToNode(id: node.id)
                        }
                        .id(node.id)
                    }
                }
                .padding(20)
                .frame(width: treeContentWidth, height: treeContentHeight)
                .frame(minWidth: 200, minHeight: 200)
            }
            .onChange(of: viewModel.currentNodeId) { oldId, newId in
                if !newId.isEmpty {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newId, anchor: .center)
                    }
                }
            }
            .onAppear {
                // Initial scroll to current node
                if !viewModel.currentNodeId.isEmpty {
                    proxy.scrollTo(viewModel.currentNodeId, anchor: .center)
                }
            }
        }
        .background(Color.black.opacity(0.02))
        .cornerRadius(8)
    }

    private var treeContentWidth: CGFloat {
        (viewModel.treeWidth * spacingX) + 60
    }

    private var treeContentHeight: CGFloat {
        (viewModel.treeHeight * spacingY) + 60
    }
}

struct TreeEdgeView: View {
    let edge: TreeVisualEdge
    let spacingX: CGFloat
    let spacingY: CGFloat
    let nodeSize: CGFloat

    var body: some View {
        Path { path in
            let startX = edge.from.x * spacingX + nodeSize/2
            let startY = edge.from.y * spacingY + nodeSize/2
            let endX = edge.to.x * spacingX + nodeSize/2
            let endY = edge.to.y * spacingY + nodeSize/2
            path.move(to: CGPoint(x: startX, y: startY))
            path.addLine(to: CGPoint(x: endX, y: endY))
        }
        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
    }
}

struct TreeNodeView: View {
    let node: TreeVisualNode
    let isCurrent: Bool
    let spacingX: CGFloat
    let spacingY: CGFloat
    let nodeSize: CGFloat
    let action: () -> Void

    var body: some View {
        let posX = node.x * spacingX + nodeSize/2
        let posY = node.y * spacingY + nodeSize/2

        Group {
            if isCurrent {
                currentMarker
            } else {
                stoneMarker
            }
        }
        .position(x: posX, y: posY)
        .onTapGesture(perform: action)
    }

    private var currentMarker: some View {
        Rectangle()
            .fill(Color.blue)
            .frame(width: nodeSize, height: nodeSize)
            .rotationEffect(.degrees(45))
            .overlay(
                Rectangle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .rotationEffect(.degrees(45))
            )
            .shadow(color: .blue.opacity(0.3), radius: 2)
    }

    private var stoneMarker: some View {
        Circle()
            .fill(node.color == .black ? Color.black : (node.color == .white ? Color.white : Color.gray.opacity(0.4)))
            .frame(width: nodeSize, height: nodeSize)
            .overlay(
                Circle().stroke(Color.black.opacity(0.2), lineWidth: 0.5)
            )
    }
}

struct VariationMarker: View {
    let label: String
    let theme: BoardTheme
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.5))
            .frame(width: size * 0.4, height: size * 0.4)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.3), lineWidth: 1)
            )
            .shadow(radius: 1)
    }
}
