import Foundation
import SwiftUI
import Combine

enum Language: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
}

class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @AppStorage("selectedLanguage") var selectedLanguage: Language = .english

    init() {
        // If no value is stored, try to detect system language
        if UserDefaults.standard.string(forKey: "selectedLanguage") == nil {
            let locale = Locale.current.language.languageCode?.identifier ?? "en"
            if locale.contains("zh") {
                self.selectedLanguage = .chinese
            } else {
                self.selectedLanguage = .english
            }
        }
    }

    func localizedString(_ key: String) -> String {
        let path = Bundle.main.path(forResource: selectedLanguage.rawValue, ofType: "lproj")
        let bundle = path != nil ? Bundle(path: path!) : Bundle.main
        return NSLocalizedString(key, bundle: bundle ?? .main, comment: "")
    }
}

extension String {
    var localized: String {
        LanguageManager.shared.localizedString(self)
    }
}
