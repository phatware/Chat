//
//  Created by Alex.M on 20.06.2022.
//

import Foundation
import Combine
import UIKit
import AVFoundation

@MainActor
final class ChatViewModel: ObservableObject {

    @Published private(set) var fullscreenAttachmentItem: Optional<Attachment> = nil
    @Published var fullscreenAttachmentPresented = false

    @Published var fileToShare: URL?
    @Published var fileSharePresented = false

    @Published var fileToPreview: URL?
    @Published var filePreviewPresented = false

    @Published var messageMenuRow: MessageRow?

    /// The messages frame that is currently being rendered in the Message Menu
    /// - Note: Used to further refine a messages frame (instead of using the cell boundary), mainly used for positioning reactions
    @Published var messageFrame: CGRect = .zero

    /// Provides a mechanism to issue haptic feedback to the user
    /// - Note: Used when launching the MessageMenu

    let inputFieldId = UUID()

    /// Task for auto-clearing clipboard (cancellable on deinit)
    private var clipboardClearTask: Task<Void, Never>?

    var didSendMessage: (DraftMessage) -> Void = {_ in }
    var didUpdateAttachmentStatus: (AttachmentUploadUpdate) -> Void = { _ in }
    var inputViewModel: InputViewModel?
    var globalFocusState: GlobalFocusState?

    func presentAttachmentFullScreen(_ attachment: Attachment) {
        // For video files, check if playable and show fullscreen video preview
        if attachment.isVideoFile {
            Task {
                let canPlay = await checkVideoPlayable(url: attachment.full)
                if canPlay {
                    // Show fullscreen video preview
                    fullscreenAttachmentItem = attachment
                    fullscreenAttachmentPresented = true
                } else {
                    // Fall back to share sheet
                    presentFileShare(attachment)
                }
            }
            return
        }

        // For GIF file attachments, show fullscreen animated viewer
        if attachment.isGIF {
            fullscreenAttachmentItem = attachment
            fullscreenAttachmentPresented = true
            return
        }

        // For regular files, show QuickLook preview if supported, otherwise share sheet
        if attachment.type == .file {
            presentFilePreviewOrShare(attachment)
            return
        }
        fullscreenAttachmentItem = attachment
        fullscreenAttachmentPresented = true
    }

    /// Check if a video URL is playable
    private func checkVideoPlayable(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            return try await asset.load(.isPlayable)
        } catch {
            return false
        }
    }

    func dismissAttachmentFullScreen() {
        fullscreenAttachmentPresented = false
        fullscreenAttachmentItem = nil
    }

    func presentFileShare(_ attachment: Attachment) {
        fileToShare = attachment.full
        fileSharePresented = true
    }

    func dismissFileShare() {
        fileSharePresented = false
        fileToShare = nil
    }

    func presentFilePreviewOrShare(_ attachment: Attachment) {
        let url = attachment.full
        if QuickLookPreview.canPreview(url) {
            fileToPreview = url
            filePreviewPresented = true
        } else {
            presentFileShare(attachment)
        }
    }

    func dismissFilePreview() {
        filePreviewPresented = false
        fileToPreview = nil
    }

    func updateAttachmentStatus(_ uploadUpdate: AttachmentUploadUpdate) {
      didUpdateAttachmentStatus(uploadUpdate)
    }

    func sendMessage(_ message: DraftMessage) {
        didSendMessage(message)
    }

    func messageMenuAction() -> (Message, DefaultMessageMenuAction) -> Void {
        { [weak self] message, action in
            self?.messageMenuActionInternal(message: message, action: action)
        }
    }

    func messageMenuActionInternal(message: Message, action: DefaultMessageMenuAction) {
        switch action {
        case .copy:
            // Cancel any previous clipboard clear task
            clipboardClearTask?.cancel()

            // Check for image attachment first
            if let imageAttachment = message.attachments.first(where: { $0.type == .image }),
               let imageData = try? Data(contentsOf: imageAttachment.full),
               let image = UIImage(data: imageData) {
                UIPasteboard.general.image = image
                // Auto-clear clipboard after 120 seconds for security
                // Store PNG data for reliable comparison (UIImage == uses pointer comparison)
                let copiedImageData = image.pngData()
                clipboardClearTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 120_000_000_000) // 120 seconds
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        // Compare image data, not pointer
                        if let currentImage = UIPasteboard.general.image,
                           let currentData = currentImage.pngData(),
                           currentData == copiedImageData {
                            UIPasteboard.general.image = nil
                        }
                    }
                    self?.clipboardClearTask = nil
                }
            } else if !message.text.isEmpty {
                // Fall back to copying text
                let copiedText = message.text
                UIPasteboard.general.string = copiedText
                // Auto-clear clipboard after 120 seconds for security
                clipboardClearTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 120_000_000_000) // 120 seconds
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        if UIPasteboard.general.string == copiedText {
                            UIPasteboard.general.string = ""
                        }
                    }
                    self?.clipboardClearTask = nil
                }
            }
        case .reply:
            inputViewModel?.attachments.replyMessage = message.toReplyMessage()
            globalFocusState?.focus = .uuid(inputFieldId)
        case .retry:
            // Retry action is handled by the app via onMessageMenuAction closure
            break
        case .resend:
            // Resend action is handled by the app via onMessageMenuAction closure
            break
        case .edit(let saveClosure):
            inputViewModel?.text = message.text
            inputViewModel?.edit(saveClosure)
            globalFocusState?.focus = .uuid(inputFieldId)
        case .share:
            // Share file, video, or recording
            if let fileAttachment = message.attachments.first(where: { $0.type == .file }) {
                presentFileShare(fileAttachment)
            } else if let videoAttachment = message.attachments.first(where: { $0.type == .video }) {
                presentFileShare(videoAttachment)
            } else if let recording = message.recording, let url = recording.url {
                fileToShare = url
                fileSharePresented = true
            }
        case .delete:
            // Delete action is handled by the app via onMessageMenuAction closure
            break
        }
    }
}
