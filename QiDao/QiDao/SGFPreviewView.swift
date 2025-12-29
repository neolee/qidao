import SwiftUI

struct SGFPreviewView: View {
    @ObservedObject var viewModel: BoardViewModel
    @State private var showCopiedMessage = false

    var body: some View {
        GroupBox(label: Label("SGF Preview".localized, systemImage: "doc.text")) {
            VStack(spacing: 8) {
                ScrollView {
                    Text(viewModel.gameState.sgf)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                        .textSelection(.enabled)
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

                HStack {
                    if showCopiedMessage {
                        Text("Copied!".localized)
                            .font(.caption)
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                    Spacer()
                    Button(action: copyToClipboard) {
                        Label("Copy".localized, systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(4)
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.gameState.sgf, forType: .string)

        withAnimation {
            showCopiedMessage = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedMessage = false
            }
        }
    }
}
