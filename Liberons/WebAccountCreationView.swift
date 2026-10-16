import SwiftUI
import SafariServices

struct WebAccountCreationButton: View {
    @ObservedObject var language: LanguageStore
    @State private var showingWebsite = false

    private let accountURL = URL(string: "https://liberons.com/account?source=ios")!

    var body: some View {
        Button {
            showingWebsite = true
        } label: {
            VStack(spacing: 4) {
                Text(language.text("Create an account", "Créer un compte"))
                    .fontWeight(.semibold)
                Text(language.text("Choose Free or a larger Libérons plan", "Choisissez Gratuit ou un forfait Libérons supérieur"))
                    .font(.caption)
                    .opacity(0.72)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
        }
        .buttonStyle(.bordered)
        .sheet(isPresented: $showingWebsite) {
            SafariView(url: accountURL)
                .ignoresSafeArea()
        }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
