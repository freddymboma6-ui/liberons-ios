import Foundation
import Combine

@MainActor
final class LanguageStore: ObservableObject {
    enum Language: String, CaseIterable, Identifiable {
        case english = "en"
        case french = "fr"
        var id: String { rawValue }
        var title: String { self == .english ? "English" : "Français" }
    }

    @Published var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "liberons.language") }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "liberons.language"), let value = Language(rawValue: saved) {
            language = value
        } else {
            language = Locale.preferredLanguages.first?.hasPrefix("fr") == true ? .french : .english
        }
    }

    func text(_ en: String, _ fr: String) -> String { language == .french ? fr : en }
}
