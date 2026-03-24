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
        let fixedWidth = bounds.width > 0 ? bounds.width : 250
        let size = sizeThatFits(CGSize(width: fixedWidth, height: .greatestFiniteMagnitude))
        let exceedsMax = size.height > maxHeight
        if exceedsMax != isScrollEnabled {
            isScrollEnabled = exceedsMax
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: min(size.height, maxHeight))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Recalculate height whenever layout changes
        invalidateIntrinsicContentSize()
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
            // Invalidate intrinsic size for auto-grow
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
