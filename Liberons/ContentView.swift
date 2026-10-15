import SwiftUI
import Photos

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
                    Text("Libérons").font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("Keep your memories. Free your space.").foregroundStyle(.secondary)
                }
                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress).textContentType(.emailAddress)
                        .padding().background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                    SecureField("Password", text: $password)
                        .textContentType(.password).padding()
                        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                }
                if let error = auth.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button {
                    signingIn = true
                    Task {
                        await auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                        signingIn = false
                    }
                } label: {
                    Group { if signingIn { ProgressView().tint(.white) } else { Text("Sign in").fontWeight(.semibold) } }
                        .frame(maxWidth: .infinity).frame(height: 54)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16))
                .disabled(signingIn || email.isEmpty || password.isEmpty)
                Spacer()
            }
            .padding(24)
        }
    }
}

private struct HomeView: View {
    @ObservedObject var auth: AuthStore
    @StateObject private var analyzer = PhotoLibraryAnalyzer()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your iPhone storage")
                            .font(.largeTitle.bold())
                        Text("See how much space your photos and videos are using before backing anything up.")
                            .foregroundStyle(.secondary)
                    }

                    if analyzer.canReadLibrary {
                        analysisCard
                    } else {
                        permissionCard
                    }

                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(22)
            }
            .navigationTitle("Libérons")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if analyzer.canReadLibrary && analyzer.totalItems == 0 {
                    await analyzer.scan()
                }
            }
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44))
            Text("Analyze your photo library")
                .font(.title2.bold())
            Text("Libérons needs access to your photos and videos to calculate how much space can be freed. Nothing is uploaded during this analysis.")
                .foregroundStyle(.secondary)
            Button("Allow Photo Access") {
                Task { await analyzer.requestAccessAndScan() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            if analyzer.isScanning {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Analyzing your library…").font(.headline)
                    ProgressView(value: Double(analyzer.scannedItems), total: Double(max(analyzer.totalItems, 1)))
                    Text("\(analyzer.scannedItems.formatted()) of \(analyzer.totalItems.formatted()) items")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Text(analyzer.formattedSize)
                .font(.system(size: 48, weight: .bold, design: .rounded))
            Text("estimated photo & video library")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                stat(title: "Photos", value: analyzer.photoCount.formatted(), icon: "photo")
                stat(title: "Videos", value: analyzer.videoCount.formatted(), icon: "video")
            }

            if !analyzer.isScanning {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Potentially reclaimable")
                        .font(.headline)
                    Text(analyzer.formattedSize)
                        .font(.title.bold())
                    Text("This is an estimate. Libérons will never remove an original until its cloud copy has been uploaded and verified.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                Button("Scan Again") {
                    Task { await analyzer.scan() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
    }

    private func stat(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
            Text(title).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

#Preview { ContentView() }
