import SwiftUI
import UniformTypeIdentifiers

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

                    Button(action: exportSgf) {
                        Label("Export".localized, systemImage: "square.and.arrow.up")
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

    private func exportSgf() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.init(filenameExtension: "sgf")!]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Export SGF".localized
        savePanel.message = "Choose where to save the SGF file".localized
        savePanel.nameFieldStringValue = "current_position.sgf"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try viewModel.gameState.sgf.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to save SGF: \(error)")
                }
            }
        }
    }
}
