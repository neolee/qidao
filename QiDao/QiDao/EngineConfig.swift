import Foundation
import Combine

struct EngineProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var path: String
    var model: String
    var config: String
    var extraArgs: String

    init(id: UUID = UUID(), name: String, path: String, model: String = "", config: String = "", extraArgs: String = "") {
        self.id = id
        self.name = name
        self.path = path
        self.model = model
        self.config = config
        self.extraArgs = extraArgs
    }

    static var `default`: EngineProfile {
        EngineProfile(
            name: "KataGo",
            path: "/opt/homebrew/bin/katago",
            model: "/opt/homebrew/share/go-engines/kata1-b28c512nbt-s9435149568-d4923088660.bin.gz",
            config: "/opt/homebrew/share/go-engines/analysis.cfg",
            extraArgs: ""
        )
    }
}

struct AnalysisSettings: Codable, Equatable {
    var maxVisits: Int? = 1000
    var maxTime: Double? = nil
    var iterativeDeepening: Bool = true
    var reportDuringSearchEvery: Double? = 0.5
    var includePolicy: Bool = true
    var advancedParams: [String: String] = [:]
}

enum WinRatePerspective: String, Codable, CaseIterable {
    case black = "Black"
    case current = "Current Player"
    
    var localized: String { self.rawValue.localized }
}

struct DisplaySettings: Codable, Equatable {
    var maxCandidates: Int = 20
    var showOwnership: Bool = true
    var showWinRateGraph: Bool = true
    var overlayWinRatePerspective: WinRatePerspective = .current
}

struct AppConfig: Codable {
    var currentProfileId: UUID?
    var profiles: [EngineProfile]
    var analysis: AnalysisSettings
    var display: DisplaySettings

    static var `default`: AppConfig {
        let defaultProfile = EngineProfile.default
        return AppConfig(
            currentProfileId: defaultProfile.id,
            profiles: [defaultProfile],
            analysis: AnalysisSettings(),
            display: DisplaySettings()
        )
    }
}

class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published var config: AppConfig

    private let configKey = "QiDaoAppConfig"

    private init() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = AppConfig.default
        }
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: configKey)
        }
    }

    var currentProfile: EngineProfile {
        config.profiles.first { $0.id == config.currentProfileId } ?? EngineProfile.default
    }
}
