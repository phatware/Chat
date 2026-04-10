//
//  MessageStatusProvider.swift
//  Chat
//
//  Observable store for message delivery statuses.
//  Cells read from this provider so that status transitions
//  (sending → sent → delivered) update only the tiny status
//  indicator — without triggering a UITableView cell
//  reconfiguration that would destroy and recreate images
//  and link previews.
//

import SwiftUI

@MainActor
public class MessageStatusProvider: ObservableObject {
    @Published public var statuses: [String: Message.Status] = [:]

    public init() {}

    /// Update a single message status.
    public func update(_ messageId: String, status: Message.Status?) {
        statuses[messageId] = status
    }

    /// Bulk-update statuses (initial load / full refresh).
    public func bulkUpdate(_ updates: [String: Message.Status?]) {
        for (id, status) in updates {
            statuses[id] = status
        }
    }

    /// Remove a message from tracking.
    public func remove(_ messageId: String) {
        statuses.removeValue(forKey: messageId)
    }
}
