//
//  CanvasNSView.swift
//  SewingCAD
//

import AppKit
import SwiftUI

class CanvasNSView: NSView {
    var onScroll: ((CGPoint) -> Void)?
    var onMouseMove: ((CGPoint, Bool) -> Void)?
    var onDragBegan: ((CGPoint, Bool) -> Void)?
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    var onDoubleClick: ((CGPoint) -> Void)?
    var onEnterKey: (() -> Void)?
    var onDeleteKey: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY))
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let flipped = CGPoint(x: location.x, y: bounds.height - location.y)
        let isShift = event.modifierFlags.contains(.shift)
        onMouseMove?(flipped, isShift)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let flipped = CGPoint(x: location.x, y: bounds.height - location.y)
        if event.clickCount == 2 {
            onDoubleClick?(flipped)
        } else {
            let isShift = event.modifierFlags.contains(.shift)
            onDragBegan?(flipped, isShift)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let flipped = CGPoint(x: location.x, y: bounds.height - location.y)
        onDragChanged?(flipped)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let flipped = CGPoint(x: location.x, y: bounds.height - location.y)
        if event.clickCount != 2 {
            onDragEnded?(flipped)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            onEnterKey?()
        } else if event.keyCode == 51 {
            onDeleteKey?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }
}
