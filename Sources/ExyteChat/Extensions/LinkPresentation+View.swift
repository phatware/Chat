//
//  LinkPresentation+View.swift
//  Chat
//
//  Created by Matthew Fennell on 25/03/2025.
//

// LinkPresentation is not yet updated to support strict concurrency checking.
// LPLinkMetadata is not sendable; meanwhile, startFetchingMetadata(for:) uses a background thread and runs in a
// nonisolated context.
// Therefore, LPLinkMetadata is not usable from the main actor until Apple updates the library.
// Once LinkPresentation supports structured concurrency, we should remove the @preconcurrency annotation.
@preconcurrency import LinkPresentation
import SwiftUI

/// Lightweight wrapper around LPLinkView, that allows for more convenient use from SwiftUI.
private struct LinkViewRepresentable: UIViewRepresentable {

    let metadata: LinkPreviewMetadata

    func makeUIView(context: Context) -> LPLinkView {
        switch metadata {
        case .placeholder(let url):
            LPLinkView(url: url)
        case .enriched(let metadata):
            LPLinkView(metadata: metadata)
        }
    }

    func updateUIView(_ uiView: LPLinkView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LPLinkView, context: Context) -> CGSize?
    {
        let width = proposal.width ?? uiView.intrinsicContentSize.width
        let height = proposal.height ?? uiView.intrinsicContentSize.height
        return CGSize(width: width, height: height)
    }

}

/// In our default chat view, link previews appear in the message itself.
/// Inside the message, there is limited space, and if multiple links are given, the default link preview design, with title, image, video etc takes up too much space.
/// Unfortunately, Apple does not let us customise the LPLinkView presentation (e.g. hiding the preview image), apart from modifying the view's size.
/// Therefore, create a small wrapper around LinkViewRepresentable, which presents the preview in a small "pill" form.
private struct PlaceholderOrEnrichedLinkPillView: View {

    /// The largest height without the preview image/video becoming visible.
    private static let pillHeight: CGFloat = 53

    private let metadata: LinkPreviewMetadata

    init(url: URL) {
        self.metadata = LinkPreviewMetadata.placeholder(for: url)
    }

    init(metadata: LPLinkMetadata) {
        self.metadata = LinkPreviewMetadata.enriched(with: metadata)
    }

    var body: some View {
        LinkViewRepresentable(metadata: metadata)
            .frame(height: Self.pillHeight)
    }

}

/// "Tap to preview" placeholder shown before the user has consented to load the link preview.
/// Loading link metadata involves a network request to the destination URL, which can leak the user's
/// IP address and signal that the message was read. We therefore gate metadata fetching behind an
/// explicit user tap, rather than auto-fetching as soon as the message is rendered.
///
/// The pill paints itself against `secondarySystemBackground`, so its labels use
/// absolute `.label` / `.secondaryLabel` colors. Hierarchical styles (`.primary`,
/// `.secondary`) must not be used here: they resolve against the foreground color
/// the bubble applies in `bubbleBackground`, which is white for outgoing messages
/// (`ChatTheme.colors.messageMyText`) and would render the pill invisible.
private struct TapToPreviewPillView: View {

    static let pillHeight: CGFloat = 53

    let url: URL
    let onTap: () -> Void

    private var displayHost: String {
        url.host ?? url.absoluteString
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(UIColor.secondaryLabel))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tap to preview")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                    Text(displayHost)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tap to preview link \(displayHost)")
    }

}

/// PlaceholderOrEnrichedLinkPillView has two mutually exclusive cases - either displaying a placeholder, or enriched content.
/// To switch from one case to the other, you need to create a new view.
/// This is inconvenient for consumers since you have to keep track of whether the enriched metadata has loaded or not.
///
/// Therefore, this view manages this complexity, hiding the state of whether the enriched metadata is loaded or not.
/// Since this view is the only view generating link preview metadata, it also manages the cache.
///
/// For security/privacy, metadata is not fetched automatically; the view shows a "tap to preview" placeholder
/// and only fetches once the user explicitly taps it. Cache hits are shown immediately, since a cache hit
/// implies the user already consented to load this URL earlier in the session.
struct LinkPillView: View {

    @State private var metadata: LinkPreviewMetadata
    @State private var consented: Bool
    private let url: URL
    private static let cache = LinkMetadataCache()

    init(url: URL) {
        self.url = url
        if let cached = Self.cache.get(forURL: url) {
            _metadata = State(initialValue: .enriched(with: cached))
            _consented = State(initialValue: true)
        } else {
            _metadata = State(initialValue: .placeholder(for: url))
            _consented = State(initialValue: false)
        }
    }

    private func fetchMetadata(for url: URL) async {
        let provider = LPMetadataProvider()
        let metadata = try? await provider.startFetchingMetadata(for: url)
        guard let metadata = metadata else {
            return
        }
        self.metadata = .enriched(with: metadata)
        Self.cache.insert(metadata, forURL: url)
    }

    var body: some View {
        // Use ZStack instead of Group as animation modifier doesn't work with Group.
        ZStack {
            if !consented {
                TapToPreviewPillView(url: url) {
                    consented = true
                }
            } else {
                switch metadata {
                case .placeholder(let url):
                    PlaceholderOrEnrichedLinkPillView(url: url)
                        .task {
                            await fetchMetadata(for: url)
                        }
                case .enriched(let metadata):
                    PlaceholderOrEnrichedLinkPillView(metadata: metadata)
                }
            }
        }
        .animation(.default, value: metadata)
        .animation(.default, value: consented)
    }

}

#Preview {
    LinkPillView(url: URL(string: "https://example.org")!)
}
