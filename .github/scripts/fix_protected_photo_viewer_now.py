from pathlib import Path

p = Path("Liberons/ProtectedLibraryView.swift")
s = p.read_text()
start = s.index("private struct ProtectedZoomablePhoto: UIViewRepresentable {")
end_marker = "private enum ProtectedMediaPrefetcher"
end = s.index(end_marker, start)
new = '''private struct ProtectedZoomablePhoto: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProtectedPhotoScrollView {
        let scrollView = ProtectedPhotoScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
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
        if context.coordinator.imageView.image !== image {
            context.coordinator.imageView.image = image
            context.coordinator.lastViewportSize = .zero
        }
        context.coordinator.layoutImage(in: scrollView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        weak var scrollView: UIScrollView?
        var lastViewportSize: CGSize = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
        }

        func layoutImage(in scrollView: UIScrollView) {
            let viewport = scrollView.bounds.size
            guard viewport.width > 0, viewport.height > 0,
                  let image = imageView.image,
                  image.size.width > 0, image.size.height > 0 else { return }

            // layoutSubviews is also called continuously while UIScrollView is zooming.
            // Never rewrite the image frame during a pinch: doing so fights the native
            // zoom transform and makes the photo collapse into a tiny thumbnail.
            guard viewport != lastViewportSize || imageView.bounds.size == .zero else {
                centerImage(in: scrollView)
                return
            }

            lastViewportSize = viewport
            scrollView.setZoomScale(1, animated: false)

            let fitScale = min(viewport.width / image.size.width, viewport.height / image.size.height)
            let fittedSize = CGSize(
                width: max(1, image.size.width * fitScale),
                height: max(1, image.size.height * fitScale)
            )

            imageView.transform = .identity
            imageView.frame = CGRect(origin: .zero, size: fittedSize)
            scrollView.contentSize = fittedSize
            centerImage(in: scrollView)
        }

        private func centerImage(in scrollView: UIScrollView) {
            let contentWidth = imageView.frame.width
            let contentHeight = imageView.frame.height
            let horizontal = max(0, (scrollView.bounds.width - contentWidth) * 0.5)
            let vertical = max(0, (scrollView.bounds.height - contentHeight) * 0.5)
            scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            let targetScale = min(CGFloat(2.5), scrollView.maximumZoomScale)
            let point = gesture.location(in: imageView)
            let width = imageView.bounds.width / targetScale
            let height = imageView.bounds.height / targetScale
            let zoomRect = CGRect(
                x: point.x - width * 0.5,
                y: point.y - height * 0.5,
                width: width,
                height: height
            )
            scrollView.zoom(to: zoomRect, animated: true)
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
s = s[:start] + new + s[end:]
p.write_text(s)
