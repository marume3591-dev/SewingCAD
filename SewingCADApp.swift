//
//  SewingCADApp.swift
//  SewingCAD
//
//  Created by 丸田信一 on 2026/05/02.
//

import SwiftUI

@main
struct SewingCADApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
