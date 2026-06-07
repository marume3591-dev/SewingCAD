//
//  Persistence.swift
//  SewingCAD
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let ctx = result.container.viewContext

        let p = MeasurementProfile(context: ctx)
        p.id        = UUID()
        p.name      = "サンプル"
        p.note      = "サンプルデータ"
        p.createdAt = Date()
        p.setValue(158.0, for: 19)
        p.setValue(83.0,  for: 1)
        p.setValue(76.0,  for: 0)
        p.setValue(64.0,  for: 3)
        p.setValue(91.0,  for: 5)

        try? ctx.save()
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "SewingCAD")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("CoreData load error: \(error), \(error.userInfo)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
