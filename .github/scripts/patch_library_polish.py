from pathlib import Path

p = Path("Liberons/ProtectedLibraryView.swift")
s = p.read_text()

old = '''                            if displayItems.isEmpty {
                                ContentUnavailableView(language.text("Nothing here yet", "Rien ici pour le moment"), systemImage: mediaFilter.icon, description: Text(language.text("Protected media in this category will appear here.", "Les médias protégés de cette catégorie apparaîtront ici."))).frame(maxWidth: .infinity).padding(.vertical, 42)
                            } else {'''
new = '''                            if displayItems.isEmpty && !store.items.isEmpty {
                                VStack(spacing: 10) {
                                    ProgressView()
                                    Text(language.text("Loading protected memories…", "Chargement des souvenirs protégés…"))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 42)
                            } else if displayItems.isEmpty {
                                ContentUnavailableView(language.text("Nothing here yet", "Rien ici pour le moment"), systemImage: mediaFilter.icon, description: Text(language.text("Protected media in this category will appear here.", "Les médias protégés de cette catégorie apparaîtront ici."))).frame(maxWidth: .infinity).padding(.vertical, 42)
                            } else {'''
if old not in s:
    raise SystemExit("gallery empty-state block not found")
s = s.replace(old, new, 1)

old = '''    @State private var showInfo = false
    @State private var dismissTranslation: CGSize = .zero'''
new = '''    @State private var showInfo = false
    @State private var infoDetent: PresentationDetent = .fraction(0.64)
    @State private var dismissTranslation: CGSize = .zero'''
if old not in s:
    raise SystemExit("viewer state block not found")
s = s.replace(old, new, 1)

old = '''        .sheet(isPresented: $showInfo) {
  if let current { ProtectedMediaDetail(item: current, language: language, billing: billing, closeViewer: { showInfo = false; dismiss() }).presentationDetents([.fraction(0.32), .fraction(0.64), .large]).presentationDragIndicator(.visible).presentationCornerRadius(34).presentationBackground(.regularMaterial).presentationContentInteraction(.resizes).presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.32))) }
        }'''
new = '''        .sheet(isPresented: $showInfo) {
  if let current { ProtectedMediaDetail(item: current, language: language, billing: billing, closeViewer: { showInfo = false; dismiss() }).presentationDetents([.fraction(0.32), .fraction(0.64), .large], selection: $infoDetent).presentationDragIndicator(.visible).presentationCornerRadius(34).presentationBackground(.regularMaterial).presentationContentInteraction(.resizes).presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.32))) }
        }
        .onChange(of: showInfo) { _, isPresented in
            if isPresented { infoDetent = .fraction(0.64) }
        }'''
if old not in s:
    raise SystemExit("info sheet block not found")
s = s.replace(old, new, 1)

p.write_text(s)
