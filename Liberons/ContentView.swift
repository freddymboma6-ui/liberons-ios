import SwiftUI

struct ContentView: View {
    @StateObject private var auth = AuthStore()

    var body: some View {
        Group {
            if auth.isLoading {
                ProgressView()
            } else if auth.isAuthenticated {
                HomeView(auth: auth)
            } else {
                SignInView(auth: auth)
            }
        }
    }
}

private struct SignInView: View {
    @ObservedObject var auth: AuthStore
    @State private var email = ""
    @State private var password = ""
    @State private var signingIn = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()

                VStack(spacing: 8) {
                    Text("Libérons")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("Keep your memories. Free your space.")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .padding()
                        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                }

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    signingIn = true
                    Task {
                        await auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                        signingIn = false
                    }
                } label: {
                    Group {
                        if signingIn { ProgressView().tint(.white) }
                        else { Text("Sign in").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .disabled(signingIn || email.isEmpty || password.isEmpty)

                Text("Use the Libérons account you already created.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(24)
        }
    }
}

private struct HomeView: View {
    @ObservedObject var auth: AuthStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("Connected to Libérons")
                    .font(.title2.bold())
                Text("Your account is ready. Next we'll analyze this iPhone's photo library and calculate how much space can be freed.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Sign out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                .padding(.top, 12)
            }
            .padding(28)
            .navigationTitle("Libérons")
        }
    }
}

#Preview {
    ContentView()
}
