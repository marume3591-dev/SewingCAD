//
//  ScrollDetector.swift
//  SewingCAD
//

import SwiftUI
import AppKit

struct ScrollDetector: NSViewRepresentable {
    var onScroll: (CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollNSView {
        let view = ScrollNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollNSView, context: Context) {}

    class ScrollNSView: NSView {
        var onScroll: ((CGPoint) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func scrollWheel(with event: NSEvent) {
            print("scrollWheel called: dx=\(event.scrollingDeltaX) dy=\(event.scrollingDeltaY)")
            onScroll?(CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY))
        }
    }
}
