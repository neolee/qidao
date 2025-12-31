import SwiftUI

struct GameCommentView: View {
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject private var langManager = LanguageManager.shared
    @State private var commentText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ScrollView {
                TextField("Write some game comment".localized, text: $commentText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isFocused)
                    .onChange(of: viewModel.currentNodeId) {
                        commentText = viewModel.nodeComment
                    }
                    .onChange(of: commentText) { old, new in
                        if new != viewModel.nodeComment {
                            DispatchQueue.main.async {
                                viewModel.updateNodeComment(new)
                            }
                        }
                    }
                    .onAppear {
                        commentText = viewModel.nodeComment
                    }
            }
            .padding(8)
            .background(Color.black.opacity(0.03))
            .cornerRadius(4)
        }
    }
}
