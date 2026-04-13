//
//  String+Emoji.swift
//  Chat
//

import Foundation

extension String {
    /// Returns `true` when every visible character (grapheme cluster) is an
    /// emoji and the total count is between 1 and `maxCount` (default 3).
    /// Works correctly with compound emoji: flags, skin-toned, ZWJ families, keycaps, etc.
    func isEmojiOnly(maxCount: Int = 3) -> Bool {
        guard !isEmpty else { return false }
        let count = emojiCount
        guard count >= 1 && count <= maxCount else { return false }
        // Make sure every character is an emoji (no stray text)
        return allSatisfy { $0.isEmoji }
    }

    /// Number of visible emoji glyphs (grapheme-cluster level).
    var emojiCount: Int {
        reduce(0) { $0 + ($1.isEmoji ? 1 : 0) }
    }
}

extension Character {
    /// True when the character renders as an emoji glyph.
    /// Handles simple emoji, compound sequences (ZWJ, flags, keycaps, skin tones).
    var isEmoji: Bool {
        // Multi-scalar sequences (flags, families, skin-toned) are always emoji
        if unicodeScalars.count > 1 {
            return unicodeScalars.first?.properties.isEmoji == true
        }
        guard let scalar = unicodeScalars.first else { return false }
        // Single-scalar emoji that have default emoji presentation
        if scalar.properties.isEmojiPresentation { return true }
        // Emoji above basic Latin symbols (avoids digits 0-9, #, * being treated as emoji)
        return scalar.properties.isEmoji && scalar.value > 0x238C
    }
}
