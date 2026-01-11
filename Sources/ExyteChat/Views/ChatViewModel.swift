//
//  Created by Alex.M on 20.06.2022.
//

import Foundation
import Combine
import UIKit

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
        // For files, show share sheet instead of fullscreen viewer
        if attachment.type == .file {
            presentFileShare(attachment)
            return
        }
        fullscreenAttachmentItem = attachment
        fullscreenAttachmentPresented = true
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
            } else if !message.text.isEmpty {
                // Fall back to copying text
                UIPasteboard.general.string = message.text
            }
        case .reply:
            inputViewModel?.attachments.replyMessage = message.toReplyMessage()
            globalFocusState?.focus = .uuid(inputFieldId)
        case .retry:
            // Retry action is handled by the app via onMessageMenuAction closure
            break
        case .edit(let saveClosure):
            inputViewModel?.text = message.text
            inputViewModel?.edit(saveClosure)
            globalFocusState?.focus = .uuid(inputFieldId)
        case .delete:
            // Delete action is handled by the app via onMessageMenuAction closure
            break
        }
    }
}
