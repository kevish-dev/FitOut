import Foundation
import SwiftData

enum PersistenceFactory {
    static func makeContainer(at storeURL: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: FitOutSchemaV4.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration("FitOutTests", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let url: URL
            if let storeURL {
                url = storeURL
            } else {
                let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                url = support.appendingPathComponent("FitOut", isDirectory: true).appendingPathComponent("FitOut.store")
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.deletingLastPathComponent().path)
            #endif
            configuration = ModelConfiguration("FitOut", schema: schema, url: url, cloudKitDatabase: .none)
        }
        // Failure is returned to the app. Never replace a failed persistent store with a
        // disposable in-memory database or delete the user's store to recover.
        return try ModelContainer(for: schema, migrationPlan: FitOutMigrationPlan.self, configurations: [configuration])
    }
}
