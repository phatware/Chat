//
//  AnimatedGIFView.swift
//

import SwiftUI
import Kingfisher

/// A SwiftUI view that displays an animated GIF using Kingfisher's AnimatedImageView.
/// Supports looping animation, caching, and both fill and fit content modes.
struct AnimatedGIFView: UIViewRepresentable {

    let url: URL?
    let cacheKey: String?
    let contentMode: UIView.ContentMode

    init(url: URL?, cacheKey: String? = nil, contentMode: UIView.ContentMode = .scaleAspectFill) {
        self.url = url
        self.cacheKey = cacheKey
        self.contentMode = contentMode
    }

    func makeUIView(context: Context) -> AnimatedImageView {
        let view = AnimatedImageView()
        view.contentMode = contentMode
        view.clipsToBounds = true
        view.autoPlayAnimatedImage = true
        view.repeatCount = .infinite
        return view
    }

    func updateUIView(_ uiView: AnimatedImageView, context: Context) {
        guard let url = url else {
            uiView.image = nil
            return
        }
        let resource = KF.ImageResource(downloadURL: url, cacheKey: cacheKey)
        uiView.kf.setImage(with: resource, options: [.cacheOriginalImage])
    }
}
