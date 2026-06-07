//
//  MeasurementWindowController.swift
//  SewingCAD
//

import AppKit
import SwiftUI

class MeasurementWindowController: NSWindowController, NSWindowDelegate {

    static let shared = MeasurementWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "計測テーブル"
        window.minSize = NSSize(width: 480, height: 480)
        window.isReleasedWhenClosed = false
        // メインウィンドウの上に常に表示
        window.level = .floating
        window.center()

        let view = MeasurementDetailView()
            .environment(\.managedObjectContext,
                         PersistenceController.shared.container.viewContext)
        window.contentView = NSHostingView(rootView: view)
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func open() {
        // 毎回ビューを再生成してonAppearを確実に発火させる
        let view = MeasurementDetailView()
            .environment(\.managedObjectContext,
                         PersistenceController.shared.container.viewContext)
        window?.contentView = NSHostingView(rootView: view)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
