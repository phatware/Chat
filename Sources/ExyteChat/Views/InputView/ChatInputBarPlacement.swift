//
//  ChatInputBarPlacement.swift
//
//  Where a composer sits at the bottom of the screen.
//

import SwiftUI
import UIKit

public extension View {
    /// Pads a composer row so it lines up with the system's bottom bars.
    ///
    /// iOS 26+ draws bottom bars — the search field, Messages' composer —
    /// lower than the safe area, in the home-indicator band, with matching
    /// side margins where the bar meets a window corner. iOS 27.1 reports
    /// that position (`UIView.LayoutRegion.bar`). On 26.0–27.0 it's derived
    /// from the safe area the way the system places the search field there
    /// (measured on iPhone 17e and 18 Pro: 27.8 pt above the edge with a
    /// 34 pt inset). With the keyboard up the row keeps a small gap above it
    /// instead. Before iOS 26 the row sits on the safe area, as it always has.
    ///
    /// The row's container must end at the bottom safe-area edge (the last
    /// view of a full-height stack, or a bottom `safeAreaInset`).
    ///
    /// - Parameter rowHeight: Height of the single-line row. iOS 27.1 lines
    ///   shorter bars up on the system bar's center line.
    func chatInputBarPlacement(rowHeight: CGFloat) -> some View {
        modifier(ChatInputBarPlacement(rowHeight: rowHeight))
    }
}

extension View {
    /// Liquid Glass in `shape` on iOS 26+, a flat fill before.
    @ViewBuilder
    func inputBarGlass<S: Shape>(in shape: S, fallback: Color, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(fallback, in: shape)
        }
    }
}

struct ChatInputBarPlacement: ViewModifier {
    let rowHeight: CGFloat

    @State private var metrics: BottomBarMetrics?
    @State private var isKeyboardShown = false

    /// Gap above the keyboard, and below the row when there's no bottom inset.
    private static let minimumGap: CGFloat = 8
    /// Side margin away from window corners (matches the message bubbles).
    private static let sideMargin = MessageView.horizontalScreenEdgePadding

    func body(content: Content) -> some View {
        content
            .padding(.leading, sidePadding(touchesEdge: metrics?.touchesLeadingEdge))
            .padding(.trailing, sidePadding(touchesEdge: metrics?.touchesTrailingEdge))
            .padding(.top, Self.minimumGap)
            .padding(.bottom, bottomPadding)
            .background {
                BottomBarMetricsReader(rowHeight: rowHeight) { metrics = $0 }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) {
                setKeyboardShown(true, notification: $0)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) {
                setKeyboardShown(false, notification: $0)
            }
    }

    /// Negative while the row dips below the safe area into the
    /// home-indicator band.
    private var bottomPadding: CGFloat {
        guard #available(iOS 26.0, *),
              !isKeyboardShown,
              let metrics,
              metrics.safeAreaBottom > 0 else {
            return Self.minimumGap
        }
        return metrics.barBottomGap - metrics.safeAreaBottom
    }

    /// The same margin as the bottom where the row meets a window corner,
    /// the way Messages lays its composer out.
    private func sidePadding(touchesEdge: Bool?) -> CGFloat {
        guard #available(iOS 26.0, *),
              touchesEdge == true,
              let metrics,
              metrics.safeAreaBottom > 0 else {
            return Self.sideMargin
        }
        return max(Self.sideMargin, metrics.barBottomGap)
    }

    /// Moves the row with the keyboard: SwiftUI animates the keyboard's safe
    /// area on the same curve.
    private func setKeyboardShown(_ shown: Bool, notification: Notification) {
        guard shown != isKeyboardShown else { return }
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        withAnimation(.easeOut(duration: duration)) {
            isKeyboardShown = shown
        }
    }
}

struct BottomBarMetrics: Equatable {
    /// The window's bottom safe-area inset (home indicator).
    var safeAreaBottom: CGFloat
    /// Where the system puts a bottom bar: its bottom edge's distance from
    /// the window's bottom edge.
    var barBottomGap: CGFloat
    var touchesLeadingEdge: Bool
    var touchesTrailingEdge: Bool
}

/// Reads the window geometry the placement needs from UIKit.
private struct BottomBarMetricsReader: UIViewRepresentable {
    let rowHeight: CGFloat
    let onChange: (BottomBarMetrics) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.rowHeight = rowHeight
        view.onChange = onChange
        view.report()
    }

    final class ReaderView: UIView {
        var rowHeight: CGFloat = 44
        var onChange: ((BottomBarMetrics) -> Void)?
        private var lastReported: BottomBarMetrics?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            report()
        }

        func report() {
            guard let window, bounds.width > 0 else { return }
            let safeAreaBottom = window.safeAreaInsets.bottom
            let frame = convert(bounds, to: window)
            let metrics = BottomBarMetrics(
                safeAreaBottom: safeAreaBottom,
                barBottomGap: Self.barBottomGap(in: window, rowHeight: rowHeight, safeAreaBottom: safeAreaBottom),
                touchesLeadingEdge: frame.minX <= 0.5,
                touchesTrailingEdge: frame.maxX >= window.bounds.width - 0.5
            )
            guard metrics != lastReported else { return }
            lastReported = metrics
            // Called during layout: hand the value to SwiftUI on the next turn.
            DispatchQueue.main.async { [onChange] in onChange?(metrics) }
        }

        private static func barBottomGap(in window: UIWindow, rowHeight: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
            if #available(iOS 27.1, *) {
                return window.edgeInsets(for: .bar(onEdge: UIRectEdge.bottom, extent: rowHeight)).bottom
            }
            // iOS 26.0–27.0: the search field's bottom edge sits 6.2 pt into
            // the home-indicator inset.
            return max(safeAreaBottom - 6.2, 8)
        }
    }
}
