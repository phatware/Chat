//
//  QuickLookPreview.swift
//  Chat
//
//  SwiftUI wrapper for QLPreviewController to preview documents in-app.
//

import SwiftUI
import QuickLook

/// A SwiftUI representable that wraps `QLPreviewController` for previewing files.
public struct QuickLookPreview: UIViewControllerRepresentable {
    public let url: URL
    public var onDismiss: (() -> Void)? = nil

    public init(url: URL, onDismiss: (() -> Void)? = nil) {
        self.url = url
        self.onDismiss = onDismiss
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(url: url, onDismiss: onDismiss)
    }

    public func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        let nav = UINavigationController(rootViewController: controller)
        return nav
    }

    public func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    public class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let url: URL
        let onDismiss: (() -> Void)?

        init(url: URL, onDismiss: (() -> Void)?) {
            self.url = url
            self.onDismiss = onDismiss
        }

        // MARK: - QLPreviewControllerDataSource

        public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }

        // MARK: - QLPreviewControllerDelegate

        public func previewControllerDidDismiss(_ controller: QLPreviewController) {
            onDismiss?()
        }
    }

    /// Returns `true` when iOS QuickLook can preview the file at the given URL.
    public static func canPreview(_ url: URL) -> Bool {
        QLPreviewController.canPreview(url as NSURL)
    }
}
