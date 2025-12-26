import SwiftUI

struct EngineConfigView: View {
    @ObservedObject var viewModel: BoardViewModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var configManager = ConfigManager.shared

    @State private var selectedTab: ConfigTab = .profiles
    @State private var localConfig: AppConfig = ConfigManager.shared.config
    @State private var showAdvanced: Bool = false

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
                    Spacer()
                    TextField("", value: $localConfig.analysis.maxVisits, formatter: NumberFormatter())
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Max Time (seconds)".localized)
                    Spacer()
                    TextField("", value: $localConfig.analysis.maxTime, formatter: NumberFormatter())
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }

                Toggle("Iterative Deepening".localized, isOn: $localConfig.analysis.iterativeDeepening)

                HStack {
                    Text("Report Interval (s)".localized)
                    Spacer()
                    TextField("", value: $localConfig.analysis.reportDuringSearchEvery, formatter: NumberFormatter())
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                DisclosureGroup("Advanced Parameters".localized, isExpanded: $showAdvanced) {
                    VStack(alignment: .leading) {
                        Text("Key-Value pairs for KataGo Analysis API".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)

                        ForEach(localConfig.analysis.advancedParams.keys.sorted(), id: \.self) { key in
                            HStack {
                                Text(key).frame(width: 150, alignment: .leading)
                                TextField("Value", text: Binding(
                                    get: { localConfig.analysis.advancedParams[key] ?? "" },
                                    set: { localConfig.analysis.advancedParams[key] = $0 }
                                ))
                                Button(action: { localConfig.analysis.advancedParams.removeValue(forKey: key) }) {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button(action: {
                            localConfig.analysis.advancedParams["new_param"] = "value"
                        }) {
                            Label("Add Parameter".localized, systemImage: "plus")
                        }
                        .padding(.top, 4)
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
                Stepper(value: $localConfig.display.maxCandidates, in: 1...20) {
                    HStack {
                        Text("Max Candidates".localized)
                        Spacer()
                        Text("\(localConfig.display.maxCandidates)")
                            .foregroundColor(.secondary)
                    }
                }

                Toggle("Show Ownership Map".localized, isOn: $localConfig.display.showOwnership)
                Toggle("Show Win Rate Graph".localized, isOn: $localConfig.display.showWinRateGraph)
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
