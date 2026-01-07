//
//  Created by Alex.M on 08.07.2022.
//

import SwiftUI

struct MessageTimeView: View {

    let text: String
    let userType: UserType
    var chatTheme: ChatTheme
    var expiresAt: Date?

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
                .foregroundColor(chatTheme.colors.messageTimeText(userType))

            if let expiresAt = expiresAt {
                ExpirationCountdownView(expiresAt: expiresAt)
            }
        }
    }
}

/// Displays countdown until message expiration in red
/// Updates every ~15 seconds, shows minutes remaining or "<1" for less than 1 minute
struct ExpirationCountdownView: View {
    let expiresAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let remaining = expiresAt.timeIntervalSince(context.date)

            if remaining > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "timer")
                        .font(.system(size: 9))
                    Text(formatRemaining(remaining))
                        .font(.caption)
                }
                .foregroundColor(.red)
            }
        }
    }

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "<1m"
        }
        let minutes = Int((seconds + 29)/60)
        if minutes > 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            }
            return String(format: "%d:%02d", hours, remainingMinutes)
        }
        return "\(minutes)m"
    }
}

struct MessageTimeWithCapsuleView: View {

    let text: String
    let isCurrentUser: Bool
    var chatTheme: ChatTheme
    var expiresAt: Date?

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
                .foregroundColor(.white)
                .opacity(0.8)

            if let expiresAt = expiresAt {
                ExpirationCountdownView(expiresAt: expiresAt)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
        .padding(.horizontal, 8)
        .background {
            Capsule()
                .foregroundColor(.black.opacity(0.4))
        }
    }
}

