import SwiftUI

/// Global access gate for the public Libérons app.
/// A single AuthStore and LanguageStore are shared by the normal app and the
/// restricted-account experience so access changes and localization stay in sync.
struct PublicAccessRootView: View {
    @StateObject private var auth = AuthStore()
    @StateObject private var language = LanguageStore()

    var body: some View {
        Group {
            if auth.isLoading {
                ZStack {
                    LiberonsTheme.canvas.ignoresSafeArea()
                    ProgressView()
                }
            } else if auth.isRestricted {
                RestrictedAccountView(auth: auth, language: language)
            } else {
                ContentView(auth: auth, language: language)
            }
        }
    }
}
