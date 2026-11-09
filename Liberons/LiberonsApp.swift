import SwiftUI

private struct LibéronsStoreResult: Decodable {
    let resultCount: Int
    let results: [StoreApp]
    struct StoreApp: Decodable {
        let trackId: Int?
        let version: String?
        let trackViewUrl: URL?
    }
}

@main
struct LiberonsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOptionalUpdate = false
    @State private var storeURL: URL?
    @State private var storeVersion: String?
    @AppStorage("liberons.lastSuggestedStoreVersion") private var lastSuggestedVersion = ""

    @MainActor private func checkForUpdate() async {
        guard let bundleID = Bundle.main.bundleIdentifier,
              var components = URLComponents(string: "https://itunes.apple.com/lookup") else { return }
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "ca")
        ]
        guard let url = components.url else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(LibéronsStoreResult.self, from: data)
            guard let app = result.results.first,
                  let version = app.version,
                  let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                  version.compare(installed, options: .numeric) == .orderedDescending,
                  version != lastSuggestedVersion,
                  let destination = app.trackViewUrl else { return }
            storeURL = destination
            storeVersion = version
            showOptionalUpdate = true
        } catch {
            // Unavailable App Store lookup must not block backups or browsing.
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await checkForUpdate() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await checkForUpdate() } }
                }
                .alert(
                    Locale.current.language.languageCode?.identifier == "fr"
                        ? "Nouvelle version Libérons" : "Libérons update available",
                    isPresented: $showOptionalUpdate
                ) {
                    Button(Locale.current.language.languageCode?.identifier == "fr" ? "Mettre à jour" : "Update") {
                        if let version = storeVersion { lastSuggestedVersion = version }
                        if let storeURL { UIApplication.shared.open(storeURL) }
                    }
                    Button(Locale.current.language.languageCode?.identifier == "fr" ? "Plus tard" : "Later", role: .cancel) {
                        if let version = storeVersion { lastSuggestedVersion = version }
                    }
                } message: {
                    Text(Locale.current.language.languageCode?.identifier == "fr"
                         ? "Une nouvelle version est disponible. Vous pouvez continuer à utiliser Libérons sans mettre à jour."
                         : "A new version is available. You can keep using Libérons without updating.")
                }
        }
    }
}
