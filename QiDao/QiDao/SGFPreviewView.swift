import SwiftUI
import UniformTypeIdentifiers

struct SGFPreviewView: View {
    @ObservedObject var viewModel: BoardViewModel
    @ObservedObject private var langManager = LanguageManager.shared
    @State private var showCopiedMessage = false
    @State private var isExportingSgf = false
    @State private var sgfDocument = SgfDocument()

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
        .fileExporter(
            isPresented: $isExportingSgf,
            document: sgfDocument,
            contentType: .sgf,
            defaultFilename: viewModel.currentFileUrl?.deletingPathExtension().lastPathComponent.appending("_pos.sgf") ?? "current_position.sgf"
        ) { result in
            switch result {
            case .success(let url):
                viewModel.lastSgfDirectory = url.deletingLastPathComponent()
            case .failure(let error):
                print("Failed to export SGF: \(error)")
            }
        }
        .fileDialogDefaultDirectory(viewModel.lastSgfDirectory)
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
        sgfDocument.sgfContent = viewModel.gameState.sgf
        isExportingSgf = true
    }
}
