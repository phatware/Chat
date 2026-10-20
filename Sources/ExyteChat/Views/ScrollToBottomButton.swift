//
//  ScrollToBottomButton.swift
//
//  The "scroll to latest" circle shown while a chat is scrolled up.
//

import SwiftUI

/// The chat's scroll-to-latest button: Liquid Glass on iOS 26+, the theme's
/// bubble fill with a soft shadow before. Shared by the messenger list and
/// the app's terminal transcript so both look the same.
public struct ScrollToBottomButton: View {
    private let theme: ChatTheme
    private let action: () -> Void

    public init(theme: ChatTheme, action: @escaping () -> Void) {
        self.theme = theme
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            theme.images.scrollToBottom
                .foregroundStyle(theme.colors.sendButtonBackground)
                .frame(width: 40, height: 40)
                .modifier(Chrome(fill: theme.colors.messageFriendBG))
        }
        .accessibilityLabel("Scroll to latest message")
    }

    private struct Chrome: ViewModifier {
        let fill: Color

        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: Circle())
            } else {
                content
                    .background(fill, in: Circle())
                    .shadow(color: .primary.opacity(0.1), radius: 2, y: 1)
            }
        }
    }
}
