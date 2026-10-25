from pathlib import Path

p = Path("Liberons/ProtectedLibraryView.swift")
s = p.read_text()
old = '''private struct ProtectedZoomablePhoto: View {
    let image: UIImage
    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
        }
        .ignoresSafeArea()
    }
}
'''
new = '''private struct ProtectedZoomablePhoto: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProtectedPhotoScrollView {
        let scrollView = ProtectedPhotoScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .black

        let imageView = context.coordinator.imageView
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        context.coordinator.scrollView = scrollView
        let coordinator = context.coordinator
        scrollView.onLayout = { [weak scrollView, weak coordinator] in
            guard let scrollView, let coordinator else { return }
            coordinator.layoutImage(in: scrollView)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: ProtectedPhotoScrollView, context: Context) {
        context.coordinator.imageView.image = image
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()
        context.coordinator.layoutImage(in: scrollView)
    }

    @MainActor final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        weak var scrollView: UIScrollView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage(in: scrollView) }

        func layoutImage(in scrollView: UIScrollView) {
            guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
            let size = scrollView.bounds.size
            imageView.frame = CGRect(origin: .zero, size: size)
            scrollView.contentSize = size
            centerImage(in: scrollView)
        }

        private func centerImage(in scrollView: UIScrollView) {
            let scaledWidth = imageView.bounds.width * scrollView.zoomScale
            let scaledHeight = imageView.bounds.height * scrollView.zoomScale
            let horizontal = max(0, (scrollView.bounds.width - scaledWidth) / 2)
            let vertical = max(0, (scrollView.bounds.height - scaledHeight) / 2)
            scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: true)
                return
            }
            let targetScale = min(CGFloat(2.5), scrollView.maximumZoomScale)
            let point = gesture.location(in: imageView)
            let width = scrollView.bounds.width / targetScale
            let height = scrollView.bounds.height / targetScale
            scrollView.zoom(to: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height), animated: true)
        }
    }
}

private final class ProtectedPhotoScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
'''
if old not in s:
    raise SystemExit("ProtectedZoomablePhoto source block not found")
s = s.replace(old, new, 1)
p.write_text(s)
