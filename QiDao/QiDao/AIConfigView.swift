import SwiftUI
import UniformTypeIdentifiers

struct AIConfigView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var langManager = LanguageManager.shared

    @State private var selectedTab: ConfigTab = .profiles
    @State private var localConfig: AIConfig = ConfigManager.shared.config
    @State private var showAdvanced: Bool = false
    @State private var newParamKey: String = ""
    @State private var newParamValue: String = ""

    @State private var isImportingFile = false
    @State private var selectionTarget: ConfigSelectionTarget?
    @State private var initialDirectory: URL?

    enum ConfigSelectionTarget {
        case executable
        case model
        case config
    }

    enum ConfigTab: String, CaseIterable {
        case profiles = "Engine Profiles"
        case analysis = "Analysis Config"
        case display = "Display Config"

        var localized: String { self.rawValue.localized }
    }

    var body: some View {
        NavigationSplitView {
            List(ConfigTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Text(tab.localized)
            }
            .navigationTitle("Settings".localized)
            .id(langManager.selectedLanguage)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    switch selectedTab {
                    case .profiles:
                        profilesView
                    case .analysis:
                        analysisView
                    case .display:
                        displayView
                    }
                }

                Divider()

                HStack {
                    Button("Reset to Default".localized) {
                        localConfig = AIConfig.default
                    }
                    Spacer()
                    Button("Cancel".localized) {
                        dismiss()
                    }
                    Button("Save".localized) {
                        configManager.config = localConfig
                        configManager.save()
                        // Notify viewModel to update if needed
                        viewModel.config = localConfig
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .frame(width: 700, height: 500)
        .onAppear {
            localConfig = configManager.config
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            guard let target = selectionTarget,
                  let index = localConfig.profiles.firstIndex(where: { $0.id == localConfig.currentProfileId }) else { return }

            if case .success(let urls) = result, let url = urls.first {
                switch target {
                case .executable:
                    localConfig.profiles[index].path = url.path
                case .model:
                    localConfig.profiles[index].model = url.path
                case .config:
                    localConfig.profiles[index].config = url.path
                }
            }
        }
        .fileDialogDefaultDirectory(initialDirectory)
    }

    private var profilesView: some View {
        Form {
            Section(header: Text("Select Profile".localized)) {
                Picker("Current Profile".localized, selection: $localConfig.currentProfileId) {
                    ForEach(localConfig.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }

                HStack {
                    Button(action: {
                        let newProfile = EngineProfile(name: "New Profile".localized, path: "")
                        localConfig.profiles.append(newProfile)
                        localConfig.currentProfileId = newProfile.id
                    }) {
                        Label("Add Profile".localized, systemImage: "plus")
                    }

                    if localConfig.profiles.count > 1 {
                        Button(role: .destructive, action: {
                            if let id = localConfig.currentProfileId {
                                localConfig.profiles.removeAll { $0.id == id }
                                localConfig.currentProfileId = localConfig.profiles.first?.id
                            }
                        }) {
                            Label("Delete Profile".localized, systemImage: "trash")
                        }
                    }
                }
            }

            if let index = localConfig.profiles.firstIndex(where: { $0.id == localConfig.currentProfileId }) {
                Section(header: Text("Profile Details".localized)) {
                    TextField("Name".localized, text: $localConfig.profiles[index].name)

                    HStack {
                        TextField("Executable Path".localized, text: $localConfig.profiles[index].path)
                        Button("Browse...".localized) {
                            selectionTarget = .executable
                            initialDirectory = localConfig.profiles[index].path.isEmpty ? nil : URL(fileURLWithPath: localConfig.profiles[index].path).deletingLastPathComponent()
                            isImportingFile = true
                        }
                    }

                    HStack {
                        TextField("Model Path".localized, text: $localConfig.profiles[index].model)
                        Button("Browse...".localized) {
                            selectionTarget = .model
                            initialDirectory = localConfig.profiles[index].model.isEmpty ? nil : URL(fileURLWithPath: localConfig.profiles[index].model).deletingLastPathComponent()
                            isImportingFile = true
                        }
                    }

                    HStack {
                        TextField("Config Path".localized, text: $localConfig.profiles[index].config)
                        Button("Browse...".localized) {
                            selectionTarget = .config
                            initialDirectory = localConfig.profiles[index].config.isEmpty ? nil : URL(fileURLWithPath: localConfig.profiles[index].config).deletingLastPathComponent()
                            isImportingFile = true
                        }
                    }

                    TextField("Extra Arguments".localized, text: $localConfig.profiles[index].extraArgs)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var analysisView: some View {
        Form {
            Section(header: Text("Basic Settings".localized)) {
                HStack {
                    Text("Max Visits".localized)
                        .frame(width: 160, alignment: .leading)
                    Spacer()
                    OptionalNumberField(value: $localConfig.analysis.maxVisits, placeholder: "Default".localized)
                        .frame(width: 100)
                }

                HStack {
                    Text("Full Game Analysis Max Visits".localized)
                        .frame(width: 200, alignment: .leading)
                    Spacer()
                    TextField("", value: Binding(
                        get: { localConfig.analysis.fullScanMaxVisits ?? 40 },
                        set: { localConfig.analysis.fullScanMaxVisits = $0 }
                    ), formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                HStack {
                    Text("Max Time (seconds)".localized)
                        .frame(width: 160, alignment: .leading)
                    Spacer()
                    OptionalNumberField(value: $localConfig.analysis.maxTime, placeholder: "Default".localized)
                        .frame(width: 100)
                }
                Toggle("Iterative Deepening".localized, isOn: $localConfig.analysis.iterativeDeepening)

                HStack {
                    Text("Report Interval (s)".localized)
                        .frame(width: 160, alignment: .leading)
                    Spacer()
                    OptionalNumberField(value: $localConfig.analysis.reportDuringSearchEvery, placeholder: "Default".localized)
                        .frame(width: 100)
                }
            }

            Section {
                DisclosureGroup("Advanced Parameters".localized, isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Key-Value pairs for KataGo Analysis API (overrideSettings)".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !localConfig.analysis.advancedParams.isEmpty {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Parameter".localized).font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
                                    Text("Value".localized).font(.caption.bold()).frame(maxWidth: .infinity, alignment: .trailing)
                                    Spacer().frame(width: 39)
                                }

                                ForEach(localConfig.analysis.advancedParams.keys.sorted(), id: \.self) { key in
                                    HStack {
                                        Text(key)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        TextField("", text: Binding(
                                            get: { localConfig.analysis.advancedParams[key] ?? "" },
                                            set: { localConfig.analysis.advancedParams[key] = $0 }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)

                                        Button(action: { localConfig.analysis.advancedParams.removeValue(forKey: key) }) {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                        .frame(width: 30)
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.03))
                            .cornerRadius(8)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Add New Parameter".localized).font(.caption.bold())
                            HStack(spacing: 20) {
                                TextField("key".localized, text: $newParamKey)
                                    .textFieldStyle(.roundedBorder)
                                TextField("value".localized, text: $newParamValue)
                                    .textFieldStyle(.roundedBorder)
                                Button(action: {
                                    if !newParamKey.isEmpty {
                                        localConfig.analysis.advancedParams[newParamKey] = newParamValue
                                        newParamKey = ""
                                        newParamValue = ""
                                    }
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .offset(y: -3)
                                .disabled(newParamKey.isEmpty)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var displayView: some View {
        Form {
            Section(header: Text("Board Overlay".localized)) {
                HStack {
                    Text("Max Candidates".localized)
                        .frame(width: 160, alignment: .leading)
                    Spacer()
                    TextField("", value: $localConfig.display.maxCandidates, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Stepper("", value: $localConfig.display.maxCandidates, in: 1...100)
                        .labelsHidden()
                        .controlSize(.small)
                }

                Toggle("Show Ownership Map".localized, isOn: $localConfig.display.showOwnership)
                Toggle("Show Win Rate Graph".localized, isOn: $localConfig.display.showWinRateGraph)

                VStack(alignment: .leading) {
                    HStack {
                        Text("Blunder Threshold".localized)
                        Spacer()
                        Text(String(format: "%.0f%%", localConfig.display.blunderThreshold * 100))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { localConfig.display.blunderThreshold },
                        set: { localConfig.display.blunderThreshold = ($0 * 100).rounded() / 100 }
                    ), in: 0.05...0.50)
                }
                .padding(.vertical, 4)

                HStack {
                    Text("Overlay Win Rate".localized)
                        .frame(width: 160, alignment: .leading)
                    Spacer()
                    Picker("", selection: $localConfig.display.overlayWinRatePerspective) {
                        ForEach(WinRatePerspective.allCases, id: \.self) { perspective in
                            Text(perspective.localized).tag(perspective)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct OptionalNumberField<T: LosslessStringConvertible & Equatable>: View {
    @Binding var value: T?
    let placeholder: String
    @State private var textValue: String = ""

    var body: some View {
        TextField("", text: $textValue, prompt: Text(placeholder))
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .onAppear {
                if let v = value {
                    textValue = "\(v)"
                }
            }
            .onChange(of: textValue) {
                if textValue.isEmpty {
                    value = nil
                } else if let newValue = T(textValue) {
                    value = newValue
                }
            }
            .onChange(of: value) {
                if let v = value {
                    if textValue != "\(v)" {
                        textValue = "\(v)"
                    }
                } else {
                    textValue = ""
                }
            }
    }
}
