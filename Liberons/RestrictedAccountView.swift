import SwiftUI

struct RestrictedAccountView: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var language: LanguageStore
    @State private var checking = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(Color.red.opacity(0.10)).frame(width: 86, height: 86)
                Image(systemName: "hand.raised.fill").font(.system(size: 34, weight: .semibold)).foregroundStyle(.red)
            }
            Text(language.text("Account restricted", "Compte restreint")).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(language.text(
                "Access to this Libérons account is currently restricted. Your protected photos, videos and account data remain preserved.",
                "L’accès à ce compte Libérons est actuellement restreint. Vos photos, vidéos protégées et les données du compte restent conservées."
            )).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 18)

            Button {
                checking = true
                Task { await auth.refreshRestrictionState(); checking = false }
            } label: {
                HStack { if checking { ProgressView().tint(.white) }; Text(language.text("Check access", "Vérifier l’accès")).fontWeight(.semibold) }
                    .frame(maxWidth: .infinity).frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(checking)

            Button(language.text("Sign out", "Se déconnecter")) { Task { await auth.signOut() } }
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .background(LiberonsTheme.canvas.ignoresSafeArea())
    }
}
