import SwiftUI

struct GameCommentView: View {
    @ObservedObject var viewModel: BoardViewModel
    @State private var commentText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextEditor(text: $commentText)
                .font(.system(size: 12))
                .padding(4)
                .background(Color.black.opacity(0.03))
                .cornerRadius(4)
                .focused($isFocused)
                .onChange(of: viewModel.currentNodeId) {
                    commentText = viewModel.nodeComment
                }
                .onChange(of: commentText) {
                    if commentText != viewModel.nodeComment {
                        viewModel.updateNodeComment(commentText)
                    }
                }
                .onAppear {
                    commentText = viewModel.nodeComment
                }

            if isFocused {
                HStack {
                    Spacer()
                    Text("Auto-saving...".localized)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
