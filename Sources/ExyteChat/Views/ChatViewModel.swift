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

    @Published var messageMenuRow: MessageRow?

    /// The messages frame that is currently being rendered in the Message Menu
    /// - Note: Used to further refine a messages frame (instead of using the cell boundary), mainly used for positioning reactions
    @Published var messageFrame: CGRect = .zero

    /// Provides a mechanism to issue haptic feedback to the user
    /// - Note: Used when launching the MessageMenu

    let inputFieldId = UUID()

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

        // For regular files, show share sheet instead of fullscreen viewer
        if attachment.type == .file {
            presentFileShare(attachment)
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
            // Check for image attachment first
            if let imageAttachment = message.attachments.first(where: { $0.type == .image }),
               let imageData = try? Data(contentsOf: imageAttachment.full),
               let image = UIImage(data: imageData) {
                UIPasteboard.general.image = image
                // Auto-clear clipboard after 120 seconds for security
                DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
                    if UIPasteboard.general.image == image {
                        UIPasteboard.general.image = nil
                    }
                }
            } else if !message.text.isEmpty {
                // Fall back to copying text
                let copiedText = message.text
                UIPasteboard.general.string = copiedText
                // Auto-clear clipboard after 120 seconds for security
                DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
                    if UIPasteboard.general.string == copiedText {
                        UIPasteboard.general.string = ""
                    }
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
