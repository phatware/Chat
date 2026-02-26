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
    case resend(resendClosure: @Sendable () -> Void)
    case edit(saveClosure: @Sendable (String) -> Void)
    case share
    case translate
    case delete

    public func title() -> String {
        switch self {
        case .copy:
            "Copy"
        case .reply:
            "Reply"
        case .retry:
            "Retry"
        case .resend:
            "Resend"
        case .edit:
            "Edit"
        case .share:
            "Share"
        case .translate:
            "Translate"
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
        case .resend:
            Image(systemName: "arrow.clockwise")
        case .edit:
            if #available(iOS 18.0, macCatalyst 18.0, *) {
                Image(systemName: "bubble.and.pencil")
            } else {
                Image(systemName: "square.and.pencil")
            }
        case .share:
            Image(systemName: "square.and.arrow.up")
        case .translate:
            Image(systemName: "translate")
        case .delete:
            Image(systemName: "trash")
        }
    }

    nonisolated public static func == (lhs: DefaultMessageMenuAction, rhs: DefaultMessageMenuAction) -> Bool {
        switch (lhs, rhs) {
        case (.copy, .copy),
             (.reply, .reply),
             (.retry(_), .retry(_)),
             (.resend(_), .resend(_)),
             (.edit(_), .edit(_)),
             (.share, .share),
             (.translate, .translate),
             (.delete, .delete):
            return true
        default:
            return false
        }
    }

    public static let allCases: [DefaultMessageMenuAction] = [
        .copy, .reply, .edit(saveClosure: {_ in}), .translate, .delete
    ]

    static public func menuItems(for message: Message) -> [DefaultMessageMenuAction] {
        let hasFileAttachment = message.attachments.contains { $0.type == .file }
        let hasImageAttachment = message.attachments.contains { $0.type == .image }
        let hasVideoAttachment = message.attachments.contains { $0.type == .video }
        let hasRecording = message.recording != nil

        // Check if message has error status (failed to send)
        let hasError: Bool
        if case .error(_) = message.status {
            hasError = true
        } else {
            hasError = false
        }

        // Check if message is in "sent" status (uploaded but no delivery notification)
        // and is over 2 minutes old - eligible for resend
        let canResend: Bool
        if case .sent = message.status {
            let twoMinutesAgo = Date().addingTimeInterval(-2 * 60)
            canResend = message.createdAt < twoMinutesAgo
        } else {
            canResend = false
        }

        if message.user.isCurrentUser {
            // For messages with error status, show Retry instead of Reply
            // For sent messages over 2 min old, show Resend instead of Reply
            let replyOrRetryOrResend: DefaultMessageMenuAction
            if hasError {
                replyOrRetryOrResend = .retry(retryClosure: {})
            } else if canResend {
                replyOrRetryOrResend = .resend(resendClosure: {})
            } else {
                replyOrRetryOrResend = .reply
            }

            if hasFileAttachment {
                // Files (including video files): no edit, no copy, add share
                return [.share, replyOrRetryOrResend, .delete]
            } else if hasVideoAttachment {
                // Video attachments: add share
                return [.share, replyOrRetryOrResend, .delete]
            } else if hasImageAttachment {
                // Images: no edit, but allow copy
                return [.copy, replyOrRetryOrResend, .delete]
            } else if hasRecording {
                // Recordings: no edit, add share
                return [.share, replyOrRetryOrResend, .delete]
            } else {
                // Text-only: all options including edit (but no edit for error/resend messages)
                if hasError || canResend {
                    return [.copy, replyOrRetryOrResend, .delete]
                } else {
                    return allCases  // includes .translate
                }
            }
        } else {
            // Peer's messages: no edit, no retry (only current user's messages can be retried)
            let hasText = !message.text.isEmpty
            if hasFileAttachment {
                // Files (including video files): no copy, add share
                return [.share, .reply, .delete]
            } else if hasVideoAttachment {
                // Video attachments: add share
                return [.share, .reply, .delete]
            } else if hasRecording {
                // Recordings: add share
                return [.share, .reply, .delete]
            } else {
                // Text or image: allow copy; add translate when there is text
                return hasText ? [.copy, .reply, .translate, .delete] : [.copy, .reply, .delete]
            }
        }
    }
}
