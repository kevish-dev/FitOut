import Foundation
import SwiftData
import Observation

@MainActor final class AppContainer {
    let defaults: UserDefaults
    let gym: GymStore
    let health: HealthAccessService
    let database: ModelContainer
    let repository: SwiftDataRepository
    let profile: ProfileStore
    let capabilities: any RuntimeCapabilityProviding

    init(database: ModelContainer, capabilities: any RuntimeCapabilityProviding = SystemCapabilityProvider(), legacyDefaults: UserDefaults? = nil, defaults: UserDefaults = .standard) throws {
        gym = try GymStore(container: database)
        self.defaults = defaults
        health = HealthAccessService(capability: capabilities, defaults: defaults)
        self.database = database
        repository = SwiftDataRepository(container: database)
        self.capabilities = capabilities
        if let legacyDefaults { try LegacyOnboardingImporter.importIfNeeded(from: legacyDefaults, into: repository) }
        profile = try ProfileStore(container: database, legacy: repository.loadSnapshot())
    }

    static func live() throws -> AppContainer {
        #if DEBUG
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--ui-test-profile"), ProcessInfo.processInfo.arguments.count > index + 1 {
            let id = ProcessInfo.processInfo.arguments[index + 1]
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ProfileUITests-" + id).appendingPathComponent("store")
            return try AppContainer(database: PersistenceFactory.makeContainer(at: url), defaults: UserDefaults(suiteName: "uitest-" + id)!)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-shell") {
            let provider = FixedCapabilityProvider(snapshot: CapabilitySnapshot(healthKit: .unavailable(.systemUnavailable), foundationModels: .unavailable(.systemUnavailable), imagePlayground: .unavailable(.systemUnavailable)))
            let container = try AppContainer(database: PersistenceFactory.makeContainer(inMemory: true), capabilities: provider, defaults: UserDefaults(suiteName: "uitest-shell-" + UUID().uuidString)!)
            container.profile.draft.name = "UITest"
            container.profile.draft.primaryGoal = .fitness
            _ = container.profile.complete()
            return container
        }
        #endif
        return try AppContainer(database: PersistenceFactory.makeContainer(), legacyDefaults: .standard)
    }
}
