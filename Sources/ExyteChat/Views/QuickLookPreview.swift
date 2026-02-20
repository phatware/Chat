//
//  QuickLookPreview.swift
//  Chat
//
//  SwiftUI wrapper for QLPreviewController to preview documents in-app.
//

import SwiftUI
import QuickLook

/// A SwiftUI representable that wraps `QLPreviewController` for previewing files.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    var onDismiss: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        let nav = UINavigationController(rootViewController: controller)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let url: URL
        let onDismiss: (() -> Void)?

        init(url: URL, onDismiss: (() -> Void)?) {
            self.url = url
            self.onDismiss = onDismiss
        }

        // MARK: - QLPreviewControllerDataSource

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }

        // MARK: - QLPreviewControllerDelegate

        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            onDismiss?()
        }
    }

    /// Returns `true` when iOS QuickLook can preview the file at the given URL.
    static func canPreview(_ url: URL) -> Bool {
        QLPreviewController.canPreview(url as NSURL)
    }
}
