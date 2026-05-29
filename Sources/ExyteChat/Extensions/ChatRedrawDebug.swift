//
//  ChatRedrawDebug.swift
//  ExyteChat
//
//  TEMPORARY redraw/flash diagnostics. Remove once the chat-view
//  flashing investigation is complete. All logging is gated behind
//  `ChatRedrawDebug.enabled` and prefixed with "[chat-redraw]" so it
//  is easy to filter (e.g. via xclog) and to delete afterwards.
//

import Foundation

enum ChatRedrawDebug {
    /// Master switch. Set to `false` (or delete this file's call sites) to
    /// silence all redraw diagnostics.
    static let enabled = false

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        print("[chat-redraw] \(message())")
    }
}
