import SwiftUI

/// Global access gate for the public Libérons app.
/// Restriction is monitored independently from the normal UI so an Owner action
/// can take over immediately without adding polling to the application screens.
struct PublicAccessRootView: View {
    @StateObject private var auth = AuthStore()
    @StateObject private var language = LanguageStore()
    @State private var showProtectedFiles = false

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
                ContentView(auth: auth)
                    .overlay(alignment: .bottomTrailing) {
                        if auth.isAuthenticated {
                            Button {
                                showProtectedFiles = true
                            } label: {
                                Image(systemName: "folder.fill.badge.plus")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 50, height: 50)
                                    .background(.blue, in: Circle())
                                    .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
                            }
                            .accessibilityLabel(language.text("Protected files", "Fichiers protégés"))
                            .padding(.trailing, 16)
                            .padding(.bottom, 70)
                        }
                    }
                    .sheet(isPresented: $showProtectedFiles) {
                        ProtectedFilesView(language: language)
                    }
            }
        }
    }
}