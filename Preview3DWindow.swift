//
//  Preview3DWindow.swift
//  SewingCAD
//

import AppKit
import SwiftUI

class Preview3DWindowController: NSObject {
    private var window: NSWindow?

    static let shared = Preview3DWindowController()

    func open(canvasState: CanvasState, projectManager: ProjectManager) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            refresh(canvasState: canvasState, projectManager: projectManager)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // クラッシュ防止: 閉じても自動解放しない
        window.isReleasedWhenClosed = false
        window.title = "3D プレビュー - SewingCAD"
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        window.delegate = self

        let contentView = Preview3DView(
            canvasState: canvasState,
            projectManager: projectManager
        )
        .environment(\.managedObjectContext,
                     PersistenceController.shared.container.viewContext)

        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func refresh(canvasState: CanvasState, projectManager: ProjectManager) {
        guard let window = window else { return }
        let contentView = Preview3DView(
            canvasState: canvasState,
            projectManager: projectManager
        )
        .environment(\.managedObjectContext,
                     PersistenceController.shared.container.viewContext)
        window.contentView = NSHostingView(rootView: contentView)
    }
}

extension Preview3DWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // isReleasedWhenClosed = false なので nil 代入だけで安全
        window = nil
    }
}
