import Foundation
import SwiftData
import Observation

@MainActor final class AppContainer {
    let database: ModelContainer
    let repository: SwiftDataRepository
    let onboarding: OnboardingStore
    let capabilities: any RuntimeCapabilityProviding

    init(database: ModelContainer, capabilities: any RuntimeCapabilityProviding = SystemCapabilityProvider(), legacyDefaults: UserDefaults? = nil) throws {
        self.database = database
        repository = SwiftDataRepository(container: database)
        self.capabilities = capabilities
        if let legacyDefaults { try LegacyOnboardingImporter.importIfNeeded(from: legacyDefaults, into: repository) }
        onboarding = try OnboardingStore(repository: repository)
    }

    static func live() throws -> AppContainer {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-shell") {
            let provider = FixedCapabilityProvider(snapshot: CapabilitySnapshot(healthKit: .unavailable(.systemUnavailable), foundationModels: .unavailable(.systemUnavailable), imagePlayground: .unavailable(.systemUnavailable)))
            let container = try AppContainer(database: PersistenceFactory.makeContainer(inMemory: true), capabilities: provider)
            container.onboarding.profile.name = "UITest"
            _ = container.onboarding.complete()
            return container
        }
        #endif
        return try AppContainer(database: PersistenceFactory.makeContainer(), legacyDefaults: .standard)
    }
}
