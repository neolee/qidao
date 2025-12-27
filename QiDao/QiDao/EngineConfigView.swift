import SwiftUI

struct EngineConfigView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var configManager = ConfigManager.shared

    @State private var selectedTab: ConfigTab = .profiles
    @State private var localConfig: AppConfig = ConfigManager.shared.config
    @State private var showAdvanced: Bool = false
    @State private var newParamKey: String = ""
    @State private var newParamValue: String = ""

    enum ConfigTab: String, CaseIterable {
        case profiles = "Engine Profiles"
        case analysis = "Analysis"
        case display = "Display"

        var localized: String { self.rawValue.localized }
    }

    var body: some View {
        NavigationSplitView {
            List(ConfigTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Text(tab.localized)
            }
            .navigationTitle("Settings".localized)
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
                        localConfig = AppConfig.default
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
                            selectFile(canChooseDirectories: false) { url in
                                localConfig.profiles[index].path = url.path
                            }
                        }
                    }

                    HStack {
                        TextField("Model Path".localized, text: $localConfig.profiles[index].model)
                        Button("Browse...".localized) {
                            selectFile(canChooseDirectories: false) { url in
                                localConfig.profiles[index].model = url.path
                            }
                        }
                    }

                    HStack {
                        TextField("Config Path".localized, text: $localConfig.profiles[index].config)
                        Button("Browse...".localized) {
                            selectFile(canChooseDirectories: false) { url in
                                localConfig.profiles[index].config = url.path
                            }
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
