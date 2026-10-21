import SwiftUI
import AVKit

/// Photos-style viewer that deliberately separates horizontal paging from vertical dismissal.
/// Once a downward gesture is locked, the pager is hidden and only the active media follows the finger.
struct ProtectedGalleryViewerV2: View {
    let items: [ProtectedCloudMedia]
    let initialID: UUID
    @ObservedObject var language: LanguageStore
    @ObservedObject var billing: CloudStorageSummary

    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID
    @State private var showInfo = false
    @State private var dismissOffset: CGFloat = 0
    @State private var verticalDismissLocked = false
    @State private var isDismissing = false

    private let indexByID: [UUID: Int]

    init(items: [ProtectedCloudMedia], initialID: UUID, language: LanguageStore, billing: CloudStorageSummary) {
        self.items = items
        self.initialID = initialID
        self.language = language
        self.billing = billing
        self.indexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        _selection = State(initialValue: initialID)
    }

    private var currentIndex: Int? { indexByID[selection] }
    private var current: ProtectedCloudMedia? {
        guard let index = currentIndex, items.indices.contains(index) else { return nil }
        return items[index]
    }

    private var dismissProgress: CGFloat {
        min(max(dismissOffset / 360, 0), 1)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(Double(1 - dismissProgress * 0.94)).ignoresSafeArea()

            // Horizontal paging exists only while the gesture is not a vertical dismissal.
            TabView(selection: $selection) {
                ForEach(items) { item in
                    ProtectedViewerMediaPage(item: item, language: language, billing: billing)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .opacity(verticalDismissLocked ? 0 : 1)
            .allowsHitTesting(!verticalDismissLocked && !isDismissing)

            // During dismissal, detach the current media from the pager so adjacent pages can never leak in.
            if verticalDismissLocked, let current {
                ProtectedViewerMediaPage(item: current, language: language, billing: billing)
                    .ignoresSafeArea()
                    .offset(y: dismissOffset)
                    .scaleEffect(1 - dismissProgress * 0.10)
                    .clipShape(RoundedRectangle(cornerRadius: dismissProgress * 30, style: .continuous))
                    .shadow(color: .black.opacity(Double(dismissProgress * 0.30)), radius: 22, y: 10)
                    .allowsHitTesting(false)
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.plain)

                    if let index = currentIndex {
                        Text("\(index + 1) / \(items.count)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.45), in: Capsule())
                    }

                    Spacer()

                    Button { showInfo = true } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                Spacer()
            }
            .opacity(verticalDismissLocked ? Double(max(0, 1 - dismissProgress * 3.2)) : 1)
            .allowsHitTesting(!verticalDismissLocked)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { value in
                    guard !isDismissing else { return }
                    let x = value.translation.width
                    let y = value.translation.height

                    if !verticalDismissLocked {
                        guard y > 5, abs(y) > abs(x) * 1.18 else { return }
                        verticalDismissLocked = true
                    }

                    guard verticalDismissLocked else { return }
                    dismissOffset = max(0, y)
                }
                .onEnded { value in
                    guard verticalDismissLocked, !isDismissing else { return }
                    let y = max(dismissOffset, value.translation.height)
                    let projected = max(y, value.predictedEndTranslation.height)

                    if y > 105 || projected > 210 {
                        isDismissing = true
                        withAnimation(.easeOut(duration: 0.20)) {
                            dismissOffset = max(y, UIScreen.main.bounds.height * 0.78)
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(145))
                            dismiss()
                        }
                    } else {
                        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.12)) {
                            dismissOffset = 0
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(280))
                            verticalDismissLocked = false
                        }
                    }
                }
        )
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showInfo) {
            if let current {
                ProtectedViewerMediaDetail(item: current, language: language, billing: billing, closeViewer: {
                    showInfo = false
                    dismiss()
                })
                .presentationDetents([.fraction(0.46), .fraction(0.72), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
                .presentationBackground(.regularMaterial)
                .presentationContentInteraction(.resizes)
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.46)))
            }
        }
    }
}
