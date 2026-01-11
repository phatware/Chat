//
//  MessageMenu+Action.swift
//  Chat
//

import SwiftUI

public protocol MessageMenuAction: Equatable, CaseIterable {
    func title() -> String
    func icon() -> Image
    
    static func menuItems(for message: Message) -> [Self]
}

extension MessageMenuAction {
    public static func menuItems(for message: Message) -> [Self] {
        Self.allCases.map { $0 }
    }
}

public enum DefaultMessageMenuAction: MessageMenuAction, Sendable {

    case copy
    case reply
    case retry(retryClosure: @Sendable () -> Void)
    case edit(saveClosure: @Sendable (String) -> Void)
    case delete

    public func title() -> String {
        switch self {
        case .copy:
            "Copy"
        case .reply:
            "Reply"
        case .retry:
            "Retry"
        case .edit:
            "Edit"
        case .delete:
            "Delete"
        }
    }

    public func icon() -> Image {
        switch self {
        case .copy:
            Image(systemName: "doc.on.doc")
        case .reply:
            Image(systemName: "arrowshape.turn.up.left")
        case .retry:
            Image(systemName: "arrow.clockwise")
        case .edit:
            if #available(iOS 18.0, macCatalyst 18.0, *) {
                Image(systemName: "bubble.and.pencil")
            } else {
                Image(systemName: "square.and.pencil")
            }
        case .delete:
            Image(systemName: "trash")
        }
    }

    nonisolated public static func == (lhs: DefaultMessageMenuAction, rhs: DefaultMessageMenuAction) -> Bool {
        switch (lhs, rhs) {
        case (.copy, .copy),
             (.reply, .reply),
             (.retry(_), .retry(_)),
             (.edit(_), .edit(_)),
             (.delete, .delete):
            return true
        default:
            return false
        }
    }

    public static let allCases: [DefaultMessageMenuAction] = [
        .copy, .reply, .edit(saveClosure: {_ in}), .delete
    ]

    static public func menuItems(for message: Message) -> [DefaultMessageMenuAction] {
        let hasFileAttachment = message.attachments.contains { $0.type == .file }
        let hasImageAttachment = message.attachments.contains { $0.type == .image }
        let hasRecording = message.recording != nil

        // Check if message has error status (failed to send)
        let hasError: Bool
        if case .error(_) = message.status {
            hasError = true
        } else {
            hasError = false
        }

        if message.user.isCurrentUser {
            // For messages with error status, show Retry instead of Reply
            let replyOrRetry: DefaultMessageMenuAction = hasError ? .retry(retryClosure: {}) : .reply

            if hasFileAttachment {
                // Files: no edit, no copy
                return [replyOrRetry, .delete]
            } else if hasImageAttachment {
                // Images: no edit, but allow copy
                return [.copy, replyOrRetry, .delete]
            } else if hasRecording {
                // Recordings: no edit, but allow copy
                return [.copy, replyOrRetry, .delete]
            } else {
                // Text-only: all options including edit (but no edit for error messages)
                if hasError {
                    return [.copy, replyOrRetry, .delete]
                } else {
                    return allCases
                }
            }
        } else {
            // Peer's messages: no edit, no retry (only current user's messages can be retried)
            if hasFileAttachment {
                // Files: no copy
                return [.reply, .delete]
            } else {
                // Text, images, or recordings: allow copy
                return [.copy, .reply, .delete]
            }
        }
    }
}
