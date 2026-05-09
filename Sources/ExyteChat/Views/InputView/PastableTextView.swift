//
//  PastableTextView.swift
//  ExyteChat
//
//  Intercepts paste operations for images and files,
//  similar to how iMessage handles pasted media.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// UITextView subclass that intercepts paste to detect images and files
/// and sizes itself to fit its content (like a multiline TextField).
final class PasteInterceptingTextView: UITextView {

    var onPasteImage: ((UIImage) -> Void)?
    var onPasteVideo: ((Data, String) -> Void)?
    var onPasteFileData: ((Data, String, String) -> Void)?
    var maxHeight: CGFloat = 120
    var markdownFormattingEnabled = false

    override var intrinsicContentSize: CGSize {
        // Once we've grown past maxHeight scrolling is enabled and the height
        // is pinned. Re-measuring `sizeThatFits` here on every layout pass
        // would force TextKit to reshape the *entire* string (height-unbounded
        // layout) — which for long multilingual paste (mixed scripts, complex
        // clusters from another app) costs many ms per call. On every scroll
        // tick this produced a feedback loop with `layoutSubviews` →
        // `invalidateIntrinsicContentSize` → Auto Layout → `intrinsicContentSize`
        // and stalled the input view. Pin to maxHeight while scrolling; the
        // measurement runs again only when text changes (see Coordinator).
        if isScrollEnabled {
            return CGSize(width: UIView.noIntrinsicMetric, height: maxHeight)
        }

        let fixedWidth = bounds.width > 0 ? bounds.width : 250
        let size = sizeThatFits(CGSize(width: fixedWidth, height: .greatestFiniteMagnitude))
        let exceedsMax = size.height > maxHeight
        if exceedsMax != isScrollEnabled {
            isScrollEnabled = exceedsMax
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: min(size.height, maxHeight))
    }

    // Note: previously `layoutSubviews` called `invalidateIntrinsicContentSize()`
    // on every layout pass, which caused an O(N²) feedback loop while scrolling
    // within long pasted text (each scroll tick fires layoutSubviews → invalidate
    // → Auto Layout → intrinsicContentSize → full-string TextKit layout). Auto-
    // grow is now driven solely by `textViewDidChange` in the Coordinator, which
    // is the only event that can actually change the required height.

    /// UTTypes that this text view's `paste(_:)` knows how to consume.
    /// Used by both the paste pipeline and `canPerformAction(_:withSender:)`
    /// so the system shows a "Paste" menu entry whenever the pasteboard
    /// holds any of these — not only when it also holds text. Without
    /// this, copying an image inside the app (which writes only
    /// `public.png` to the pasteboard) leaves UITextView's default
    /// `canPerformAction` returning false for `.paste`, so the menu
    /// item never appears even though our `paste(_:)` would handle it.
    /// iMessages happens to put text alongside the image, which is why
    /// pasting from iMessages "just works" with the default behaviour.
    private static let acceptedPasteTypes: [UTType] = [
        .mpeg4Movie, .movie, .quickTimeMovie, .video,
        .image, .png, .jpeg, .gif, .heic, .heif, .webP, .tiff, .bmp,
        .pdf,
        .fileURL,
    ]

    /// True if the system pasteboard holds anything our `paste(_:)`
    /// override knows how to handle (image / video / PDF / file URL).
    private var pasteboardHasAcceptableNonTextContent: Bool {
        let pb = UIPasteboard.general
        if pb.hasImages { return true }
        let ids = Self.acceptedPasteTypes.map(\.identifier)
        if pb.contains(pasteboardTypes: ids) { return true }
        if let urls = pb.urls, urls.contains(where: { $0.isFileURL }) { return true }
        return false
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            // Enable Paste when the pasteboard holds either text (the
            // UITextView default) or any media type our `paste(_:)`
            // override knows how to consume. Without this, in-app
            // image copies (image-only pasteboard, no string) leave
            // the "Paste" menu item hidden because UITextView only
            // considers text by default.
            if pasteboardHasAcceptableNonTextContent { return true }
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let pb = UIPasteboard.general

        // 1. Video data (MP4, MOV, etc.)
        let videoTypes: [UTType] = [.mpeg4Movie, .movie, .quickTimeMovie, .video]
        for vType in videoTypes {
            if let videoData = pb.data(forPasteboardType: vType.identifier), !videoData.isEmpty {
                let ext = vType == .quickTimeMovie ? "mov" : "mp4"
                onPasteVideo?(videoData, "pasted_video.\(ext)")
                return
            }
        }

        // 2. Images (PNG, JPEG, GIF, HEIC, etc.)
        if pb.hasImages, let image = pb.image {
            onPasteImage?(image)
            return
        }

        // 3. PDF data
        if let pdfData = pb.data(forPasteboardType: UTType.pdf.identifier), !pdfData.isEmpty {
            onPasteFileData?(pdfData, "pasted.pdf", "application/pdf")
            return
        }

        // 4. File URLs copied from Files app or Finder
        if let urls = pb.urls {
            for url in urls where url.isFileURL {
                guard let data = try? Data(contentsOf: url) else { continue }
                let fileName = url.lastPathComponent
                let ext = url.pathExtension.lowercased()
                let mime = UTType(filenameExtension: ext)?.preferredMIMEType
                    ?? "application/octet-stream"
                onPasteFileData?(data, fileName, mime)
                return
            }
        }

        // 5. Default: paste as text
        super.paste(sender)
    }
}

/// SwiftUI wrapper around `PasteInterceptingTextView`.
struct PastableTextView: UIViewRepresentable {

    @Binding var text: String
    var placeholder: String
    var textColor: UIColor
    var placeholderColor: UIColor
    var font: UIFont
    var maxHeight: CGFloat
    var markdownFormattingEnabled: Bool = false
    var isFocused: Bool
    var onFocusChange: ((Bool) -> Void)?
    var onPasteImage: ((UIImage) -> Void)?
    var onPasteVideo: ((Data, String) -> Void)?
    var onPasteFileData: ((Data, String, String) -> Void)?

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PasteInterceptingTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: min(size.height, maxHeight))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PasteInterceptingTextView {
        let tv = PasteInterceptingTextView()
        tv.delegate = context.coordinator
        tv.font = font
        tv.textColor = textColor
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.maxHeight = maxHeight
        tv.markdownFormattingEnabled = markdownFormattingEnabled
        tv.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.required, for: .vertical)

        // Placeholder label
        let label = UILabel()
        label.text = placeholder
        label.textColor = placeholderColor
        label.font = font
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: tv.textContainer.lineFragmentPadding == 0
                ? tv.leadingAnchor : tv.leadingAnchor,
                constant: tv.textContainerInset.left + 4),
            label.centerYAnchor.constraint(equalTo: tv.centerYAnchor)
        ])
        context.coordinator.placeholderLabel = label
        label.isHidden = !text.isEmpty

        tv.onPasteImage = onPasteImage
        tv.onPasteVideo = onPasteVideo
        tv.onPasteFileData = onPasteFileData
        return tv
    }

    func updateUIView(_ tv: PasteInterceptingTextView, context: Context) {
        // Sync text
        if tv.text != text {
            tv.text = text
        }
        tv.textColor = textColor
        tv.font = font
        tv.maxHeight = maxHeight
        tv.markdownFormattingEnabled = markdownFormattingEnabled
        context.coordinator.placeholderLabel?.isHidden = !text.isEmpty

        // Sync callbacks
        tv.onPasteImage = onPasteImage
        tv.onPasteVideo = onPasteVideo
        tv.onPasteFileData = onPasteFileData

        // Sync focus
        if isFocused, !tv.isFirstResponder {
            DispatchQueue.main.async { tv.becomeFirstResponder() }
        } else if !isFocused, tv.isFirstResponder {
            DispatchQueue.main.async { tv.resignFirstResponder() }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PastableTextView
        weak var placeholderLabel: UILabel?

        init(_ parent: PastableTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            placeholderLabel?.isHidden = !(textView.text ?? "").isEmpty
            // Auto-grow: text changed, so the cached "isScrollEnabled" decision
            // may no longer hold (e.g. user just deleted enough to shrink below
            // maxHeight). Reset scroll enablement and let `intrinsicContentSize`
            // re-measure once. Without this reset, the early-return in
            // `intrinsicContentSize` would keep us pinned at maxHeight forever
            // after the first time the text grew past it.
            textView.isScrollEnabled = false
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange?(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange?(false)
        }
    }
}
