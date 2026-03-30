//
//  ZoomableImageView.swift
//

import SwiftUI

#if canImport(UIKit)
import UIKit
import Kingfisher

struct ZoomableImageView: UIViewRepresentable {

    let url: URL
    let cacheKey: String?
    @Binding var isZoomed: Bool

    func makeUIView(context: Context) -> ZoomableScrollView {
        let view = ZoomableScrollView()
        view.onZoomChanged = { zoomed in
            DispatchQueue.main.async {
                isZoomed = zoomed
            }
        }
        loadImage(into: view)
        return view
    }

    func updateUIView(_ uiView: ZoomableScrollView, context: Context) {}

    private func loadImage(into zoomView: ZoomableScrollView) {
        let resource: KF.ImageResource
        if let cacheKey = cacheKey {
            resource = KF.ImageResource(downloadURL: url, cacheKey: cacheKey)
        } else {
            resource = KF.ImageResource(downloadURL: url)
        }

        KingfisherManager.shared.retrieveImage(with: resource) { result in
            if case let .success(value) = result {
                DispatchQueue.main.async {
                    zoomView.setImage(value.image)
                }
            }
        }
    }
}

// MARK: - ZoomableScrollView

final class ZoomableScrollView: UIView, UIScrollViewDelegate {

    var onZoomChanged: ((Bool) -> Void)?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()

    private let maxZoomScale: CGFloat = 5.0
    private let doubleTapZoomScale: CGFloat = 3.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = maxZoomScale
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        imageView.contentMode = .scaleAspectFit

        addSubview(scrollView)
        scrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
    }

    func setImage(_ image: UIImage) {
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.contentSize = image.size
        updateZoomScale()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateZoomScale()
    }

    private func updateZoomScale() {
        guard let image = imageView.image, bounds.size != .zero else { return }

        let widthScale = bounds.width / image.size.width
        let heightScale = bounds.height / image.size.height
        let minScale = min(widthScale, heightScale)

        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = max(minScale * maxZoomScale, 1.0)

        if scrollView.zoomScale < minScale || scrollView.zoomScale == 1.0 {
            scrollView.zoomScale = minScale
        }

        centerImageView()
    }

    private func centerImageView() {
        let boundsSize = scrollView.bounds.size
        let contentSize = scrollView.contentSize

        let offsetX = max((boundsSize.width - contentSize.width) / 2, 0)
        let offsetY = max((boundsSize.height - contentSize.height) / 2, 0)

        imageView.center = CGPoint(
            x: contentSize.width / 2 + offsetX,
            y: contentSize.height / 2 + offsetY
        )
    }

    // MARK: - Double tap

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let location = gesture.location(in: imageView)
            let targetScale = scrollView.minimumZoomScale * doubleTapZoomScale
            let size = CGSize(
                width: scrollView.bounds.width / targetScale,
                height: scrollView.bounds.height / targetScale
            )
            let origin = CGPoint(
                x: location.x - size.width / 2,
                y: location.y - size.height / 2
            )
            scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
        }
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageView()
        let isZoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
        onZoomChanged?(isZoomed)
    }

    func resetZoom() {
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
    }
}

#endif
