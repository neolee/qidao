import SwiftUI

struct EngineConfigView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var langManager = LanguageManager.shared

    @State private var enginePath: String = ""
    @State private var engineArgs: String = ""
    @State private var engineModel: String = ""
    @State private var maxVisits: Int = 100

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AI Engine Configuration".localized)
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            Form {
                Section(header: Text("Engine Executable".localized)) {
                    HStack {
                        TextField("Path to KataGo".localized, text: $enginePath)
                        Button("Browse...".localized) {
                            selectFile(canChooseDirectories: false) { url in
                                enginePath = url.path
                            }
                        }
                    }
                }

                Section(header: Text("Model File".localized)) {
                    HStack {
                        TextField("Path to .bin.gz".localized, text: $engineModel)
                        Button("Browse...".localized) {
                            selectFile(canChooseDirectories: false) { url in
                                engineModel = url.path
                            }
                        }
                    }
                }

                Section(header: Text("Arguments".localized)) {
                    TextField("Additional arguments".localized, text: $engineArgs)
                        .help("e.g. analysis -config gtp_custom.cfg")
                }

                Section(header: Text("Analysis Settings".localized)) {
                    Stepper(value: $maxVisits, in: 10...10000, step: 10) {
                        HStack {
                            Text("Max Visits".localized)
                            Spacer()
                            Text("\(maxVisits)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            HStack {
                Button("Reset to Default".localized) {
                    resetToDefaults()
                }
                Spacer()
                Button("Cancel".localized) {
                    dismiss()
                }
                Button("Save".localized) {
                    saveConfig()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 450)
        .onAppear {
            loadCurrentConfig()
        }
    }

    private func loadCurrentConfig() {
        enginePath = viewModel.enginePath
        engineArgs = viewModel.engineArgs
        engineModel = viewModel.engineModel
        maxVisits = UserDefaults.standard.integer(forKey: "maxVisits")
        if maxVisits == 0 { maxVisits = 100 }
    }

    private func saveConfig() {
        viewModel.enginePath = enginePath
        viewModel.engineArgs = engineArgs
        viewModel.engineModel = engineModel
        UserDefaults.standard.set(maxVisits, forKey: "maxVisits")
        
        // If engine is running, we might want to restart it, 
        // but for now let's just update the values.
    }

    private func resetToDefaults() {
        enginePath = "/opt/homebrew/bin/katago"
        engineArgs = "analysis -config /opt/homebrew/share/go-engines/analysis.cfg"
        engineModel = ""
        maxVisits = 100
    }

    private func selectFile(canChooseDirectories: Bool, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = canChooseDirectories
        panel.canChooseFiles = !canChooseDirectories
        if panel.runModal() == .OK {
            if let url = panel.url {
                completion(url)
            }
        }
    }
}
