import SwiftUI

/// Global access gate for the public Libérons app.
/// It keeps the authenticated session alive for support while preventing a
/// restricted account from ever reaching the normal application UI.
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
                ContentView()
            }
        }
    }
}
