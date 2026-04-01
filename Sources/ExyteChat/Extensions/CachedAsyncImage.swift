//
//  Created by Aman Kumar on 26/08/25.
//

import SwiftUI
import Kingfisher

/// Configure and manage Kingfisher image cache.
public enum ImageCacheManager {
    private static var configured = false

    /// Configure Kingfisher cache limits (called once automatically).
    static func ensureConfigured() {
        guard !configured else { return }
        configured = true
        // Cap memory cache at 50 MB
        ImageCache.default.memoryStorage.config.totalCostLimit = 50 * 1024 * 1024
        // Keep at most 50 images in memory
        ImageCache.default.memoryStorage.config.countLimit = 50
        // Expire memory-cached images after 5 minutes of non-use
        ImageCache.default.memoryStorage.config.expiration = .seconds(300)
        // Disable Kingfisher's disk cache — we already manage temp files ourselves
        ImageCache.default.diskStorage.config.sizeLimit = 0
    }

    /// Clear all images from Kingfisher's in-memory cache.
    /// Call when navigating away from a chat to free image memory immediately.
    public static func clearMemoryCache() {
        ImageCache.default.clearMemoryCache()
    }
}

/// A view that asynchronously loads and displays an image using Kingfisher.
///
///     CachedAsyncImage(url: URL(string: "https://example.com/icon.png"))
///         .frame(width: 200, height: 200)
///
/// You can specify a custom cache key:
///
///     CachedAsyncImage(url: URL(string: "https://example.com/icon.png"), cacheKey: "custom-key")
///
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct CachedAsyncImage<Content>: View where Content: View {

    @State private var phase: AsyncImagePhase

    private let url: URL?
    private let cacheKey: String?
    private let scale: CGFloat
    private let transaction: Transaction
    private let content: (AsyncImagePhase) -> Content

    public var body: some View {
        content(phase)
            .task(id: url, load)
    }

    /// Loads and displays an image from the specified URL.
    public init(url: URL?, cacheKey: String? = nil, scale: CGFloat = 1) where Content == Image {
        self.init(url: url, cacheKey: cacheKey, scale: scale) { phase in
    #if os(macOS)
            phase.image ?? Image(nsImage: .init())
    #else
            phase.image ?? Image(uiImage: .init())
    #endif
        }
    }


    /// Loads and displays a modifiable image with placeholder.
    public init<I, P>(
        url: URL?,
        cacheKey: String? = nil,
        scale: CGFloat = 1,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == _ConditionalContent<I, P>, I: View, P: View {
        self.init(url: url, cacheKey: cacheKey, scale: scale) { phase in
            if let image = phase.image {
                content(image)
            } else {
                placeholder()
            }
        }
    }


    /// Loads and displays a modifiable image in phases.
    public init(
        url: URL?,
        cacheKey: String? = nil,
        scale: CGFloat = 1,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        ImageCacheManager.ensureConfigured()

        self.url = url
        self.cacheKey = cacheKey
        self.scale = scale
        self.transaction = transaction
        self.content = content

        // Synchronously check the in-memory cache so that when a cell is
        // reconfigured (e.g. on message status change) the image is never
        // replaced with a placeholder flash before the async load completes.
        // Only the memory store is queried here — disk I/O must stay async.
        var initialPhase: AsyncImagePhase = .empty
        if let url = url {
            let key = cacheKey ?? url.absoluteString
            if let cached = ImageCache.default.retrieveImageInMemoryCache(forKey: key) {
                #if canImport(UIKit)
                initialPhase = .success(Image(uiImage: cached))
                #elseif canImport(AppKit)
                initialPhase = .success(Image(nsImage: cached))
                #endif
            }
        }
        self._phase = State(wrappedValue: initialPhase)
    }

    @Sendable
    private func load() async {
        guard let url = url else {
            withAnimation(transaction.animation) { phase = .empty }
            return
        }

        let resource = KF.ImageResource(downloadURL: url, cacheKey: cacheKey)

        do {
            let image = try await withCheckedThrowingContinuation { continuation in
                KingfisherManager.shared.retrieveImage(
                    with: resource,
                    options: [
                        .cacheOriginalImage,
                        .scaleFactor(scale)
                    ]
                ) { result in
                    switch result {
                    case .success(let value):
                        print("[CachedAsyncImage] Loaded image from: \(value.cacheType)")
                        continuation.resume(returning: value.image)
                    case .failure(let error):
                        print("[CachedAsyncImage] Failed to load image: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
            }

            withAnimation(transaction.animation) {
                #if canImport(UIKit)
                phase = .success(Image(uiImage: image))
                #elseif canImport(AppKit)
                phase = .success(Image(nsImage: image))
                #else
                phase = .success(Image(uiImage: image)) // fallback for iOS-only targets
                #endif
            }
        } catch {
            withAnimation(transaction.animation) {
                phase = .failure(error)
            }
        }
    }
}