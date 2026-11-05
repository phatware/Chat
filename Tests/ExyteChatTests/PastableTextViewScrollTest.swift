//
//  PastableTextViewScrollTest.swift
//  Chat
//
//  The message field grows to `maxHeight`, then must scroll: with scrolling
//  off, the lines past the cap are laid out below the field and the caret
//  can't be brought back into view.
//

import SwiftUI
import Testing
import UIKit

@testable import ExyteChat

@MainActor
@Suite(.serialized)
struct PastableTextViewScrollTest {

    private static let maxHeight: CGFloat = 120
    private static let longText = (1...30).map { "Line \($0)" }.joined(separator: "\n")

    /// Hosts the field the way InputView does (vertical fixedSize, finite width)
    /// in a real window and returns the live UITextView.
    private func host(_ initialText: String) async -> (UIWindow, PasteInterceptingTextView, Box) {
        let box = Box(text: initialText)
        let root = Harness(box: box, maxHeight: Self.maxHeight)
        let controller = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        await settle(window)
        let tv = findTextView(in: window)!
        return (window, tv, box)
    }

    /// Lays out and yields the main queue, so the field's deferred work
    /// (`DispatchQueue.main.async`) runs before the test looks.
    private func settle(_ window: UIWindow, passes: Int = 5) async {
        for _ in 0..<passes {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func findTextView(in view: UIView) -> PasteInterceptingTextView? {
        if let tv = view as? PasteInterceptingTextView { return tv }
        for sub in view.subviews {
            if let tv = findTextView(in: sub) { return tv }
        }
        return nil
    }

    @Test func longTextScrolls() async {
        let (window, tv, _) = await host(Self.longText)
        #expect(tv.bounds.height <= Self.maxHeight + 0.5)
        #expect(tv.isScrollEnabled)
        #expect(tv.contentSize.height > tv.bounds.height)
        _ = window
    }

    @Test func typingPastTheCapScrolls() async {
        let (window, tv, box) = await host("short")
        #expect(!tv.isScrollEnabled)

        // A keystroke: UIKit changes the text, then tells the delegate.
        tv.text = Self.longText
        tv.delegate?.textViewDidChange?(tv)
        await settle(window)

        #expect(box.text == Self.longText)
        #expect(tv.bounds.height <= Self.maxHeight + 0.5)
        #expect(tv.isScrollEnabled)
    }

    /// The real composer (ChatView's message InputView), not a bare host.
    @Test func chatComposerScrolls() async {
        let chat = ChatView(messages: []) { _ in }
        let controller = UIHostingController(rootView: chat)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        await settle(window)
        guard let tv = findTextView(in: window) else {
            Issue.record("no text view in ChatView")
            return
        }
        tv.becomeFirstResponder()
        await settle(window)
        // Typed the way the keyboard does it, a line at a time.
        for line in 1...12 {
            tv.insertText(line == 1 ? "Line 1" : "\nLine \(line)")
            await settle(window, passes: 1)
        }
        await settle(window)

        #expect(tv.isFirstResponder)
        #expect(tv.bounds.height <= Self.maxHeight + 0.5)
        #expect(tv.isScrollEnabled)
        tv.resignFirstResponder()
    }

    @Test func shrinkingBelowTheCapStopsScrolling() async {
        let (window, tv, _) = await host(Self.longText)
        #expect(tv.isScrollEnabled)

        tv.text = "short"
        tv.delegate?.textViewDidChange?(tv)
        await settle(window)

        #expect(!tv.isScrollEnabled)
        #expect(tv.bounds.height < Self.maxHeight)
    }
}

@MainActor
private final class Box: ObservableObject {
    @Published var text: String
    init(text: String) { self.text = text }
}

private struct Harness: View {
    @ObservedObject var box: Box
    let maxHeight: CGFloat

    var body: some View {
        VStack {
            Spacer()
            PastableTextView(
                text: $box.text,
                placeholder: "Message",
                textColor: .label,
                placeholderColor: .placeholderText,
                font: .preferredFont(forTextStyle: .body),
                maxHeight: maxHeight,
                isFocused: false
            )
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 7)
            .padding(.leading, 16)
        }
        .frame(width: 300)
    }
}
