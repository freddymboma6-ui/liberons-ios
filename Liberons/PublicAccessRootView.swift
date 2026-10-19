import SwiftUI

/// Global access gate for the public Libérons app.
/// Restriction is monitored independently from the normal UI so an Owner action
/// can take over immediately without adding polling to the application screens.
struct PublicAccessRootView: View {
    @StateObject private var auth = AuthStore()

    var body: some View {
        Group {
            if auth.isLoading {
                ZStack {
                    LiberonsTheme.canvas.ignoresSafeArea()
                    ProgressView()
                }
            } else if auth.isRestricted {
                // Create the language store when the restricted experience is shown.
                // LanguageStore restores the user's persisted EN/FR choice.
                RestrictedAccountView(auth: auth, language: LanguageStore())
            } else {
                ContentView()
            }
        }
    }
}
