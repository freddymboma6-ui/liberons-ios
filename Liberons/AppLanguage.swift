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
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "liberons.language")
            NotificationCenter.default.post(name: .liberonsLanguageChanged, object: language.rawValue)
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "liberons.language"), let value = Language(rawValue: saved) {
            language = value
        } else {
            language = Locale.preferredLanguages.first?.hasPrefix("fr") == true ? .french : .english
        }
    }

    func text(_ en: String, _ fr: String) -> String {
        // `pending_bytes` represents storage reserved for media that has not yet
        // reached the final protected state. It is not necessarily transferring
        // over the network right now, so avoid implying an active upload.
        if en == "Being protected" && fr == "En cours de protection" {
            return language == .french ? "À protéger" : "To protect"
        }
        return language == .french ? fr : en
    }
}

extension Notification.Name {
    static let liberonsLanguageChanged = Notification.Name("liberons.language.changed")
}
