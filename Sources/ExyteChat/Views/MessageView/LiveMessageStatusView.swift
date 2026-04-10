//
//  LiveMessageStatusView.swift
//  Chat
//
//  Thin wrapper around MessageStatusView that reads status from a
//  MessageStatusProvider (ObservableObject) instead of the Message struct.
//  Only this small view re-evaluates when a status changes — the parent
//  MessageView body (with images, link previews, etc.) is untouched.
//

import SwiftUI

struct LiveMessageStatusView: View {
    @ObservedObject var provider: MessageStatusProvider
    let messageId: String
    /// Fallback status from the Message struct (used on first render
    /// before the provider is populated, or when provider has no entry).
    let fallbackStatus: Message.Status?
    let onRetry: () -> Void

    var body: some View {
        let status = provider.statuses[messageId] ?? fallbackStatus
        if let status {
            MessageStatusView(status: status, onRetry: onRetry)
        }
    }
}
