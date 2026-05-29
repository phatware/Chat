//
//  SwiftUIView.swift
//
//
//  Created by Alex.M on 07.07.2022.
//

import SwiftUI
import UIKit

@MainActor
struct MessageTextView: View {

    @Environment(\.chatTheme) private var theme
    /// Optional host-supplied renderer for the message body (e.g. MarkdownUI
    /// for agent-mode bubbles). When non-nil it replaces the default Text
    /// rendering path; URL detection / link previews still run on top.
    @Environment(\.chatMessageBodyRenderer) private var customBodyRenderer

    /// Tracks whether a long message is expanded to show full text
    @State private var isExpanded: Bool = false

    /// Large enough to show the domain and icon, if needed, for most pages.
    private static let minLinkPreviewWidth: CGFloat = 140

    /// Maximum characters to show before truncating with "..."
    private static let maxTruncatedCharacters: Int = 300

    let text: String
    let messageStyler: (String) -> AttributedString
    let userType: UserType
    let shouldShowLinkPreview: (URL) -> Bool
    let messageLinkPreviewLimit: Int
    let trailingReservedText: Text?

    /// Whether the text exceeds the truncation limit
    private var shouldTruncate: Bool {
        text.count > Self.maxTruncatedCharacters
    }

    /// The text to display (truncated or full based on expansion state)
    private var displayText: String {
        if shouldTruncate && !isExpanded {
            return Self.safeTruncated(text, limit: Self.maxTruncatedCharacters)
        }
        return text
    }

    /// Truncate `text` for the collapsed preview without ever cutting inside a
    /// line or inside a multiline markdown/equation block.
    ///
    /// Rules:
    /// - The cut only ever lands on a line boundary (`\n`), so single-line
    ///   constructs (bold, italic, inline code, inline `\(…\)` math) are never
    ///   split mid-token.
    /// - Boundaries that fall inside a multiline block are skipped until the
    ///   block closes: fenced code (``` / ~~~), display math `$$…$$`, and
    ///   bracket math `\[…\]` / `\(…\)`. Math delimiters inside a code fence are
    ///   treated as literal text.
    /// - If no safe boundary exists at/after `limit` (e.g. one very long line,
    ///   or an unterminated block), the full text is shown rather than risk
    ///   corrupting the markdown.
    static func safeTruncated(_ text: String, limit: Int) -> String {
        let chars = Array(text)
        let n = chars.count
        guard n > limit else { return text }

        var inFence = false
        var fenceChar: Character = "`"
        var inDollarMath = false   // $$ … $$
        var inBracketMath = false  // \[ … \]
        var inParenMath = false    // \( … \)
        var atLineStart = true
        var i = 0

        while i < n {
            let c = chars[i]

            // Stay in "line start" through any leading spaces.
            if atLineStart && c == " " {
                i += 1
                continue
            }

            // Fenced code block markers (``` or ~~~), only at the start of a line.
            if atLineStart && (c == "`" || c == "~") {
                var j = i
                while j < n && chars[j] == c { j += 1 }
                if j - i >= 3 {
                    if inFence {
                        if c == fenceChar { inFence = false }
                    } else if !inDollarMath && !inBracketMath && !inParenMath {
                        inFence = true
                        fenceChar = c
                    }
                    atLineStart = false
                    i = j
                    continue
                }
            }

            if c == "\n" {
                if i >= limit && !inFence && !inDollarMath && !inBracketMath && !inParenMath {
                    return String(chars[0..<i]) + "\n…"
                }
                atLineStart = true
                i += 1
                continue
            }

            // Math delimiters are only meaningful outside code fences.
            if !inFence {
                if c == "$", i + 1 < n, chars[i + 1] == "$", !inBracketMath, !inParenMath {
                    inDollarMath.toggle()
                    atLineStart = false
                    i += 2
                    continue
                }
                if c == "\\", i + 1 < n, !inDollarMath {
                    switch chars[i + 1] {
                    case "[": inBracketMath = true;  atLineStart = false; i += 2; continue
                    case "]": inBracketMath = false; atLineStart = false; i += 2; continue
                    case "(": inParenMath = true;    atLineStart = false; i += 2; continue
                    case ")": inParenMath = false;   atLineStart = false; i += 2; continue
                    default: break
                    }
                }
            }

            atLineStart = false
            i += 1
        }

        return text
    }

    var styledText: AttributedString {
        var result = displayText.styled(using: messageStyler)
        result.foregroundColor = theme.colors.messageText(userType)

        // Detect plain-text URLs that the styler didn't already mark as links
        let plainString = String(result.characters)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let matches = detector.matches(in: plainString, range: NSRange(plainString.startIndex..., in: plainString))
            for match in matches {
                guard let matchRange = Range(match.range, in: plainString),
                      let attrRange = Range(matchRange, in: result),
                      let url = match.url else { continue }
                // Only add link if the styler hasn't already set one
                if result[attrRange].link == nil {
                    let scheme = url.scheme?.lowercased() ?? ""
                    if scheme == "http" || scheme == "https" || scheme == "mailto" {
                        result[attrRange].link = url
                    }
                }
            }
        }

        for (link, range) in result.runs[\.link] {
            if link != nil {
                result[range].underlineStyle = .single
            }
        }

        return result
    }

    var urlsToPreview: [URL] {
        Array(styledText.urls.filter(shouldShowLinkPreview).prefix(messageLinkPreviewLimit))
    }

    private var renderedText: Text {
        if let trailingReservedText {
            return Text("\(Text(styledText))\(trailingReservedText.foregroundColor(.clear))")
        }
        return Text(styledText)
    }

    /// Compute the text's single-line intrinsic width via NSAttributedString.
    /// This is layout-independent, so using it for the link preview width
    /// cannot create a feedback loop (unlike measuring via GeometryReader).
    private var intrinsicTextWidth: CGFloat {
        let nsAttr = NSAttributedString(styledText)
        let bounds = nsAttr.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        )
        return ceil(bounds.width)
    }

    @ViewBuilder
    private var bodyContent: some View {
        // Ask the host renderer first; it may opt out per-message (e.g. only
        // render markdown for incoming agent messages and let outgoing user
        // text keep the default styling). When it accepts, we still honour
        // the same truncation/expand contract the default Text path uses —
        // pass the (possibly truncated) `displayText` so long agent replies
        // collapse the same way long plain-text messages do.
        if let renderer = customBodyRenderer, let customView = renderer(displayText, userType) {
            customView
                .contentShape(Rectangle())
                .accessibilityLabel(displayText)
                .applyIf(shouldTruncate) {
                    $0.onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                }
        } else {
            renderedText
                .contentShape(Rectangle())
                .accessibilityLabel(displayText)
                .environment(\.openURL, OpenURLAction { url in
                    let scheme = url.scheme?.lowercased() ?? ""
                    if scheme == "http" || scheme == "https" || scheme == "mailto" {
                        return .systemAction
                    }
                    return .discarded
                })
                .applyIf(shouldTruncate) {
                    $0.onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                }
        }
    }

    var body: some View {
        if !styledText.characters.isEmpty {
            VStack(alignment: .leading) {
                bodyContent

                // We use .enumerated(), and \.offset as the id, so that a message with duplicate links will show a preview for each.
                if !urlsToPreview.isEmpty {
                    let previewIdealWidth = max(intrinsicTextWidth, Self.minLinkPreviewWidth)
                    VStack {
                        ForEach(Array(urlsToPreview.enumerated()), id: \.offset) { _, url in
                            LinkPillView(url: url)
                        }
                    }
                    // minWidth: at least minLinkPreviewWidth (140)
                    // maxWidth: at most the text's intrinsic single-line width
                    // When the proposal is narrower than intrinsicTextWidth (text wraps),
                    // the preview naturally fills the proposal — matching the wrapped text width.
                    .frame(minWidth: Self.minLinkPreviewWidth, maxWidth: previewIdealWidth, alignment: .leading)
                }
            }
        }
    }
}

struct MessageTextView_Previews: PreviewProvider {
    static var previews: some View {
        MessageTextView(
            text: "Look at [this website](https://example.org)",
            messageStyler: AttributedString.init, userType: .other,
            shouldShowLinkPreview: { _ in true }, messageLinkPreviewLimit: 8, trailingReservedText: nil)
        MessageTextView(
            text: "Look at [this website](https://example.org)",
            messageStyler: String.markdownStyler, userType: .other,
            shouldShowLinkPreview: { _ in true }, messageLinkPreviewLimit: 8, trailingReservedText: nil)
        MessageTextView(
            text: "[@Dan](mention://user/123456789) look at [this website](https://example.org)!",
            messageStyler: String.markdownStyler, userType: .other,
            shouldShowLinkPreview: { $0.scheme != "mention" }, messageLinkPreviewLimit: 8, trailingReservedText: nil)
        // Long text preview - should show truncated with "..." and expand on tap
        MessageTextView(
            text: "This is a very long message that exceeds the 300 character limit. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.",
            messageStyler: AttributedString.init, userType: .other,
            shouldShowLinkPreview: { _ in true }, messageLinkPreviewLimit: 8, trailingReservedText: nil)
    }
}
