//
//  ChatInputAccessoryConfiguration.swift
//  ExyteChat
//
//  Host-supplied hook for customising the underlying UITextView used by the
//  chat input. Lets callers override the keyboard type, attach
//  `inputAssistantItem` bar groups (e.g. a slash-command shortcut bar above
//  the keyboard) and observe live text changes — all without forking the
//  ExyteChat view hierarchy. The configuration is installed via the
//  `.chatInputAccessory(_:)` view modifier and read through the
//  `\.chatInputAccessory` environment value.
//

import SwiftUI
import UIKit

/// Optional configuration applied to the chat input's underlying `UITextView`.
///
/// Pass `nil` (the default) to keep stock ExyteChat behaviour. Closures are
/// invoked on the main thread.
public struct ChatInputAccessoryConfiguration {

    /// Optional keyboard type override. When non-`nil`, replaces the default
    /// `.default` keyboard. Use e.g. `.webSearch` to surface `.` on the main
    /// keyboard view while keeping a spacebar.
    public var keyboardType: UIKeyboardType?

    /// Bar button groups installed on `inputAssistantItem.leadingBarButtonGroups`.
    /// These appear in the assistant bar above the keyboard (and at the leading
    /// edge of the bar on iPad). Note: on iPhone these groups do not render in
    /// the QuickType strip — use `inputAccessoryView` for an iPhone-visible bar.
    public var leadingBarButtonGroups: [UIBarButtonItemGroup]?

    /// Bar button groups installed on `inputAssistantItem.trailingBarButtonGroups`.
    /// iPad-only (see `leadingBarButtonGroups`).
    public var trailingBarButtonGroups: [UIBarButtonItemGroup]?

    /// Custom view docked above the keyboard via the underlying text view's
    /// `inputAccessoryView`. Works on both iPhone and iPad. The host owns the
    /// view's lifetime — keep a strong reference outside the configuration so
    /// it can be reused across SwiftUI updates without dismissing the keyboard.
    public var inputAccessoryView: UIView?

    /// Called whenever the underlying text view's text changes. Mirrors the
    /// SwiftUI binding the host already drives but fires on every keystroke,
    /// which is what suggestion overlays need.
    public var onTextChange: ((String) -> Void)?

    /// Called once when the underlying text view is created so the host can
    /// hold a weak reference (e.g. to insert text into it from a bar button
    /// action). The view is held strongly by UIKit; do not retain it.
    public var onTextViewReady: ((UITextView) -> Void)?

    public init(
        keyboardType: UIKeyboardType? = nil,
        leadingBarButtonGroups: [UIBarButtonItemGroup]? = nil,
        trailingBarButtonGroups: [UIBarButtonItemGroup]? = nil,
        inputAccessoryView: UIView? = nil,
        onTextChange: ((String) -> Void)? = nil,
        onTextViewReady: ((UITextView) -> Void)? = nil
    ) {
        self.keyboardType = keyboardType
        self.leadingBarButtonGroups = leadingBarButtonGroups
        self.trailingBarButtonGroups = trailingBarButtonGroups
        self.inputAccessoryView = inputAccessoryView
        self.onTextChange = onTextChange
        self.onTextViewReady = onTextViewReady
    }
}
