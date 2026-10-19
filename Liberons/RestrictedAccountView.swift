import SwiftUI
import UIKit

struct RestrictedAccountView: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var language: LanguageStore
    @State private var checking = false
    @State private var showingSupport = false

    var body: some View {
        ZStack {
            LiberonsTheme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 74)

                    ZStack {
                        Circle()
                            .fill(.red.opacity(0.09))
                            .frame(width: 96, height: 96)
                        Circle()
                            .stroke(.red.opacity(0.10), lineWidth: 1)
                            .frame(width: 96, height: 96)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 37, weight: .semibold))
                            .foregroundStyle(.red)
                    }

                    Text(language.text("Account restricted", "Compte restreint"))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .padding(.top, 25)

                    Text(language.text(
                        "Access to this Libérons account is temporarily unavailable.",
                        "L’accès à ce compte Libérons est temporairement indisponible."
                    ))
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 18)

                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 24)
                        Text(language.text(
                            "Your protected photos, videos and account information remain preserved while access is restricted.",
                            "Vos photos, vidéos protégées et les informations de votre compte restent conservées pendant la restriction."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LiberonsTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.top, 28)

                    Button {
                        showingSupport = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.blue.opacity(0.11))
                                    .frame(width: 42, height: 42)
                                Image(systemName: "message.fill")
                                    .foregroundStyle(.blue)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(language.text("Contact support", "Contacter le support"))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(language.text("Email or chat", "E-mail ou chat"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(15)
                        .background(LiberonsTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)

                    Button {
                        guard !checking else { return }
                        checking = true
                        Task {
                            await auth.refreshRestrictionState()
                            checking = false
                        }
                    } label: {
                        HStack(spacing: 9) {
                            if checking { ProgressView().controlSize(.small) }
                            else { Image(systemName: "arrow.clockwise") }
                            Text(language.text("Check access again", "Vérifier à nouveau l’accès"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.bordered)
                    .disabled(checking)
                    .padding(.top, 18)

                    Button(language.text("Sign out", "Se déconnecter")) {
                        Task { await auth.signOut() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 22)
            }
        }
        .sheet(isPresented: $showingSupport) {
            RestrictedSupportSheet(language: language)
                .presentationDetents([.height(330)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
    }
}

private struct RestrictedSupportSheet: View {
    @ObservedObject var language: LanguageStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Libérons Support", "Support Libérons"))
                    .font(.title2.bold())
                Text(language.text(
                    "Choose how you want to contact us.",
                    "Choisissez comment vous souhaitez nous contacter."
                ))
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                supportRow(
                    icon: "envelope.fill",
                    title: language.text("Email support", "Contacter par e-mail"),
                    subtitle: "support@liberons.com"
                ) { openEmail() }

                Divider().padding(.leading, 64)

                supportRow(
                    icon: "message.fill",
                    title: language.text("Support chat", "Chat avec le support"),
                    subtitle: language.text("Open Libérons Support", "Ouvrir le support Libérons")
                ) { openSupport() }
            }
            .background(LiberonsTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(LiberonsTheme.canvas.ignoresSafeArea())
    }

    private func supportRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.11))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon).foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openEmail() {
        let subject = language.text("Libérons Support — Restricted account", "Support Libérons — Compte restreint")
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@liberons.com"
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        if let url = components.url { UIApplication.shared.open(url) }
    }

    private func openSupport() {
        guard let url = LiberonsWebDestination.support.url(for: language.language) else { return }
        UIApplication.shared.open(url)
    }
}
