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
    
    @Published var selectedLanguage: Language {
        didSet {
            if oldValue != selectedLanguage {
                UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "selectedLanguage")
            }
        }
    }
    
    init() {
        let stored = UserDefaults.standard.string(forKey: "selectedLanguage")
        if let lang = stored.flatMap(Language.init) {
            self.selectedLanguage = lang
        } else {
            // Default to system language
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
